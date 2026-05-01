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
  providers = lib.concatStringsSep "," providers;

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  preferLocalBuild = true;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  # Note: run `nix build -L` (or set `--print-build-logs`) to see this
  # live; without -L Nix buffers build output until completion.
  buildCommand = ''
    car_file="$TMPDIR/fetch.car"

    # Background poller: prints CAR size + transfer rate every 5s so you
    # can tell whether anything is actually being downloaded.
    progress_watch() {
      local target="$1"
      local prev=0 now=0 delta=0
      while true; do
        sleep 5
        if [ -f "$target" ]; then
          now=$(stat -c %s "$target" 2>/dev/null || echo 0)
          delta=$(( (now - prev) / 5 ))
          printf '[fetch-ipfs] %s: %s (%s/s)\n' \
            "$cid" \
            "$(numfmt --to=iec --suffix=B $now)" \
            "$(numfmt --to=iec --suffix=B $delta)"
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
        if car extract -f "$car_file" - > "$out"; then
          return 0
        fi
        echo "car extract failed" >&2
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
