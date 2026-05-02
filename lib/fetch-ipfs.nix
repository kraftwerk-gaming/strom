# fetch-ipfs.nix - Fixed-output derivation fetcher that retrieves a CID
# from the IPFS network using lassie (parallel HTTP gateway + bitswap +
# graphsync), extracts the file with go-car, and falls back to a plain
# HTTP URL if the IPFS path fails.
#
# Usage:
#   fetchIpfs {
#     cid = "QmXxx...";
#     fallbackUrl = "https://archive.org/download/...";
#     hash = "sha256-...";
#     name = "foo.zip";
#   }
{
  lib,
  stdenvNoCC,
  lassie,
  go-car,
  curl,
  cacert,
}:

{
  cid,
  fallbackUrl ? "",
  hash,
  name,
  # Optional expected size in bytes. When set, the progress watcher
  # prints a percentage. If unset and fallbackUrl is given, we try to
  # discover it via an HTTP HEAD on the fallback URL.
  size ? 0,
  # HTTP gateways and libp2p multiaddrs lassie should always try in addition
  # to whatever it discovers via IPNI (cid.contact). Order is informational
  # only — lassie races them in parallel.
  providers ? [
    "https://ipfs.io"
    "https://dweb.link"
  ],
}:

stdenvNoCC.mkDerivation {
  inherit name;

  nativeBuildInputs = [
    lassie
    go-car
    curl
  ];

  outputHash = hash;
  outputHashMode = "flat";
  outputHashAlgo = "sha256";

  inherit cid fallbackUrl;
  expectedSize = toString size;
  providers = lib.concatStringsSep "," providers;

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  preferLocalBuild = true;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  # Note: run `nix build -L` (or set `--print-build-logs`) to see this
  # live; without -L Nix buffers build output until completion.
  buildCommand = ''
    car_file="$TMPDIR/fetch.car"

    # Discover total size: caller-provided value wins, otherwise try a
    # HEAD request against the fallback URL, then a public IPFS gateway,
    # for a Content-Length hint. The size is only used for progress
    # display; if discovery fails the build still succeeds.
    extract_content_length() {
      awk 'BEGIN{IGNORECASE=1} /^content-length:/ {gsub("\r",""); print $2}' \
        | tail -n1
    }
    total=$expectedSize
    if [ "$total" = "0" ] && [ -n "$fallbackUrl" ]; then
      total=$(curl -fsLI --max-time 15 "$fallbackUrl" 2>/dev/null \
        | extract_content_length)
      total="''${total:-0}"
      [ "$total" != "0" ] && echo "[fetch-ipfs] discovered size $total via fallback HEAD"
    fi
    if [ "$total" = "0" ]; then
      for gw in https://ipfs.io https://dweb.link; do
        total=$(curl -fsLI --max-time 15 "$gw/ipfs/$cid" 2>/dev/null \
          | extract_content_length)
        total="''${total:-0}"
        if [ "$total" != "0" ]; then
          echo "[fetch-ipfs] discovered size $total via $gw"
          break
        fi
      done
    fi

    # Background poller: prints size + transfer rate every 5s so you
    # can tell whether anything is actually being downloaded. Also prints
    # percentage and ETA when the total is known.
    progress_watch() {
      local target="$1"
      local prev=0 now=0 delta=0
      while true; do
        sleep 5
        if [ -f "$target" ]; then
          now=$(stat -c %s "$target" 2>/dev/null || echo 0)
          delta=$(( (now - prev) / 5 ))
          if [ "$total" != "0" ] && [ "$delta" -gt 0 ]; then
            local pct=$(( now * 100 / total ))
            local eta=$(( (total - now) / delta ))
            printf '[fetch-ipfs] %s: %s / %s (%d%%, %s/s, ETA %ds)\n' \
              "$cid" \
              "$(numfmt --to=iec --suffix=B $now)" \
              "$(numfmt --to=iec --suffix=B $total)" \
              "$pct" \
              "$(numfmt --to=iec --suffix=B $delta)" \
              "$eta"
          elif [ "$total" != "0" ]; then
            local pct=$(( now * 100 / total ))
            printf '[fetch-ipfs] %s: %s / %s (%d%%, %s/s)\n' \
              "$cid" \
              "$(numfmt --to=iec --suffix=B $now)" \
              "$(numfmt --to=iec --suffix=B $total)" \
              "$pct" \
              "$(numfmt --to=iec --suffix=B $delta)"
          else
            printf '[fetch-ipfs] %s: %s (%s/s, total unknown)\n' \
              "$cid" \
              "$(numfmt --to=iec --suffix=B $now)" \
              "$(numfmt --to=iec --suffix=B $delta)"
          fi
          prev=$now
        else
          printf '[fetch-ipfs] %s: waiting for first byte...\n' "$cid"
        fi
      done
    }

    fetch_via_lassie() {
      echo "fetching $cid via lassie (providers: $providers + IPNI)"
      progress_watch "$car_file" &
      local watch_pid=$!
      trap 'kill $watch_pid 2>/dev/null || true' EXIT
      # GOLOG_LOG_LEVEL controls go-libp2p / lassie internal logs.
      # bitswap=debug shows per-block requests; lassie=debug shows
      # provider selection and retrieval state machine transitions.
      if GOLOG_LOG_LEVEL="error,lassie=debug,bitswap_client=info" \
        lassie fetch \
        --progress \
        --providers "$providers" \
        --provider-timeout 60s \
        --global-timeout 1800s \
        --output "$car_file" \
        "$cid"
      then
        kill $watch_pid 2>/dev/null || true
        echo "extracting $cid from CAR"
        if car extract -f "$car_file" - > "$out" 2>/dev/null \
          && [ -s "$out" ]; then
          return 0
        fi
        # car extract only handles UnixFS DAGs. Small files added with
        # --raw-leaves end up as a single raw-codec block (bafkrei...) with
        # no UnixFS wrapper, in which case the block bytes are the file.
        # Fall back to dumping the root block directly.
        echo "car extract produced no files; trying raw block" >&2
        if car get-block "$car_file" "$cid" > "$out" 2>/dev/null \
          && [ -s "$out" ]; then
          return 0
        fi
        echo "car extract and get-block both failed" >&2
      fi
      kill $watch_pid 2>/dev/null || true
      rm -f "$car_file" "$out"
      return 1
    }

    fetch_via_curl() {
      [ -z "$fallbackUrl" ] && return 1
      echo "fetching fallback $fallbackUrl"
      progress_watch "$out" &
      local watch_pid=$!
      trap 'kill $watch_pid 2>/dev/null || true' EXIT
      curl -fL --max-time 1800 --progress-bar --retry 3 -o "$out" "$fallbackUrl"
      local rc=$?
      kill $watch_pid 2>/dev/null || true
      return $rc
    }

    if fetch_via_lassie; then
      exit 0
    fi

    if fetch_via_curl; then
      exit 0
    fi

    echo "error: lassie and fallback both failed for $cid" >&2
    exit 1
  '';
}
