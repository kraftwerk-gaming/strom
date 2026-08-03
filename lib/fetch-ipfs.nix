# fetch-ipfs.nix - Fixed-output derivation fetcher that retrieves a CID
# from one or more HTTP IPFS gateways using aria2c. aria2c parallelises
# the download as Range requests across the given gateways, so a single
# slow / mid-stream-cutting gateway can't stall the build the way a
# CAR-streaming retriever does. Cloudflare-fronted public gateways tend
# to truncate long streamed responses; aria2c sidesteps this because each
# connection is a short, cacheable Range.
#
# Usage:
#   fetchIpfs {
#     cid = "QmXxx...";
#     fallbackUrl = "https://archive.org/download/...";
#     hash = "sha256-...";
#     name = "foo.zip";
#   }
#
# Local mirrors:
#   The caller's environment may set STROM_IPFS_GATEWAYS to a comma- or
#   space-separated list of gateway prefixes (no trailing slash, no /ipfs/).
#   Those are prepended to the public gateway list so a private/local
#   mirror is preferred while still falling back to public infrastructure.
#   The var is declared in impureEnvVars; the FOD output hash is what
#   ultimately gates correctness, so this is safe to read at build time.
{
  lib,
  stdenvNoCC,
  aria2,
  curl,
  cacert,
}:

{
  cid,
  fallbackUrl ? "",
  hash,
  name,
  # HTTP gateway prefixes (no trailing slash, no /ipfs/). aria2c will
  # request "<prefix>/ipfs/<cid>" from each and split the file across them
  # via Range. trustless-gateway.link is omitted because it returns 406
  # without an explicit `Accept: application/vnd.ipld.car` header and
  # serves CARs rather than raw bytes.
  providers ? [
    "https://ipfs.io"
    "https://dweb.link"
    "https://gateway.pinata.cloud"
    "https://w3s.link"
    "https://nftstorage.link"
  ],
}:

stdenvNoCC.mkDerivation {
  inherit name;

  nativeBuildInputs = [
    aria2
    curl
  ];

  outputHash = hash;
  outputHashMode = "flat";
  outputHashAlgo = "sha256";

  inherit cid fallbackUrl;
  providers = lib.concatStringsSep " " providers;

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  preferLocalBuild = true;

  # STROM_IPFS_GATEWAYS lets the invoking user inject extra (private/local)
  # gateways without baking their URL into the repo. Format: comma- or
  # space-separated prefixes, e.g. "https://my.gateway https://other.gw".
  impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [ "STROM_IPFS_GATEWAYS" ];

  buildCommand = ''
    # Assemble the URL list: user-injected gateways first (preferred when
    # reachable), then the public defaults. aria2c races them via Range
    # requests, so the local mirror dominates when it's fast and the
    # public ones serve as automatic failover.
    urls=""
    if [ -n "''${STROM_IPFS_GATEWAYS:-}" ]; then
      for gw in $(echo "$STROM_IPFS_GATEWAYS" | tr ',' ' '); do
        [ -n "$gw" ] && urls="$urls ''${gw%/}/ipfs/$cid"
      done
    fi
    for gw in $providers; do
      urls="$urls ''${gw%/}/ipfs/$cid"
    done

    echo "[fetch-ipfs] $cid via aria2c across:"
    for u in $urls; do echo "  $u"; done

    # --- structured download progress -----------------------------------
    # Emit "@nix {...}" JSON log lines so the Nix daemon renders this FOD
    # in the aggregate "X MiB DL" progress bar, exactly like a native
    # fetchurl. The daemon parses builder stderr untrusted, which means it
    # only admits actFileTransfer (101) activities (see Nix's
    # handleJSONLogMessage); that is precisely the download case, so we
    # open one such activity and report bytes by polling the output file
    # size. Polling the file (rather than scraping aria2c's stdout) works
    # identically for the curl fallback and survives aria2c log-format
    # changes. Field/level values mirror libstore/filetransfer.cc.
    #
    # The daemon parses the build log line by line; a "@nix {...}" line is
    # only recognised when it arrives intact (it must start with "@nix "
    # and parse as JSON). So once the poller starts, it must be the *sole*
    # writer to the log stream — otherwise aria2c's concurrent stderr
    # interleaves mid-line and the structured tick is silently dropped.
    # We therefore funnel aria2c/curl chatter to a file and only surface
    # it on total failure.
    act_id=1
    nix_emit() { printf '@nix %s\n' "$1" >&2; }

    # Probe a gateway for the total size so the bar shows a percentage.
    # Optional: if no gateway yields a Content-Length the bar just counts
    # bytes up without a denominator.
    expected=0
    for u in $urls; do
      len=$(curl -fsSL -I --max-time 20 "$u" 2>/dev/null \
        | tr -d '\r' \
        | awk 'tolower($1) == "content-length:" { print $2 }' \
        | tail -n1)
      case "$len" in
        "" | *[!0-9]*) ;;
        *)
          expected=$len
          break
          ;;
      esac
    done

    nix_emit "{\"action\":\"start\",\"id\":$act_id,\"level\":4,\"type\":101,\"text\":\"fetching $cid\",\"fields\":[\"ipfs://$cid\"]}"
    if [ "$expected" -gt 0 ]; then
      nix_emit "{\"action\":\"result\",\"id\":$act_id,\"type\":106,\"fields\":[101,$expected]}"
    fi

    # Report *allocated* blocks (st_blocks, always 512-byte units), not
    # st_size: aria2c writes each Range segment at its own offset, so with
    # a sparse file st_size jumps to the full length the moment the last
    # segment is seeked, whereas st_blocks counts only bytes actually
    # written. --file-allocation=none keeps the file sparse for this to
    # hold; the curl fallback writes sequentially, where it holds too.
    progress_poll() {
      while :; do
        if [ -f "$TMPDIR/fetch.bin" ]; then
          blocks=$(stat -c %b "$TMPDIR/fetch.bin" 2>/dev/null || echo 0)
          cur=$((blocks * 512))
          if [ "$expected" -gt 0 ] && [ "$cur" -gt "$expected" ]; then
            cur=$expected
          fi
          nix_emit "{\"action\":\"result\",\"id\":$act_id,\"type\":105,\"fields\":[$cur,$expected,0,0]}"
        fi
        sleep 1
      done
    }
    progress_poll &
    poll_pid=$!

    # Idempotent: called on every success path before the mv (so the bar
    # doesn't flash back to 0 once fetch.bin is moved away) and once more
    # via the EXIT trap as a safety net on the failure path.
    stop_poll() {
      [ -n "''${poll_pid:-}" ] || return 0
      kill "$poll_pid" 2>/dev/null || true
      wait "$poll_pid" 2>/dev/null || true
      poll_pid=""
      if [ "$expected" -gt 0 ]; then
        nix_emit "{\"action\":\"result\",\"id\":$act_id,\"type\":105,\"fields\":[$expected,$expected,0,0]}"
      fi
      nix_emit "{\"action\":\"stop\",\"id\":$act_id}"
    }
    trap stop_poll EXIT

    fetch_via_aria() {
      # --split / --max-connection-per-server control parallelism.
      # --min-split-size keeps Range chunks large enough that overhead
      # stays low; 16M is the aria2 default minimum that's also kind to
      # gateway caches.
      # --check-integrity=false: integrity is verified by Nix's outputHash.
      # --conditional-get / --allow-overwrite=true cope with restarted builds.
      # --lowest-speed-limit closes any connection delivering <=10KB/s;
      # without it aria2 keeps accepted-but-stalled gateway sockets
      # open indefinitely. The outer `timeout 3600` is a hard ceiling
      # so even pathological all-stalled state falls through to the
      # curl/fallbackUrl path instead of hanging the build forever.
      timeout 3600 aria2c \
        --console-log-level=warn \
        --summary-interval=10 \
        --connect-timeout=30 \
        --timeout=120 \
        --lowest-speed-limit=10K \
        --max-tries=5 \
        --retry-wait=10 \
        --split=8 \
        --max-connection-per-server=4 \
        --min-split-size=16M \
        --file-allocation=none \
        --check-integrity=false \
        --continue=true \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        --dir="$TMPDIR" \
        --out="fetch.bin" \
        $urls >>"$TMPDIR/fetch.log" 2>&1
    }

    # Retry the whole aria2 run, resuming each time. A gateway that accepts
    # the request and THEN fails mid-stream (ipfs.io answers 501 under load,
    # observed on a 15 GiB asset after ~3 GiB) makes aria2 abort the entire
    # download with errorCode=22, which failed the build outright. Combined
    # with --continue=true above, each attempt resumes where the last stopped
    # and re-probes every URI, so the gateways still serving out-race the
    # broken one instead of the derivation dying. Without --continue this
    # loop would restart from byte 0 every time and never finish a large
    # asset. This aria2 build has no --retry-on-* options, so the retry has
    # to live out here rather than in-process.
    fetch_via_aria_retrying() {
      attempt=1
      while [ "$attempt" -le 3 ]; do
        if fetch_via_aria; then
          return 0
        fi
        echo "[fetch-ipfs] aria2c attempt $attempt failed; resuming" >>"$TMPDIR/fetch.log"
        attempt=$((attempt + 1))
      done
      return 1
    }

    fetch_via_curl() {
      [ -z "$fallbackUrl" ] && return 1
      echo "[fetch-ipfs] fallback: $fallbackUrl" >>"$TMPDIR/fetch.log"
      # No --progress-bar: our poller owns the log stream; curl's progress
      # would interleave with it and corrupt structured ticks.
      curl -fL --max-time 1800 --retry 3 \
        -o "$TMPDIR/fetch.bin" "$fallbackUrl" >>"$TMPDIR/fetch.log" 2>&1
    }

    if fetch_via_aria_retrying; then
      stop_poll
      mv "$TMPDIR/fetch.bin" "$out"
      exit 0
    fi

    if fetch_via_curl; then
      stop_poll
      mv "$TMPDIR/fetch.bin" "$out"
      exit 0
    fi

    # Total failure: stop the poller first so it no longer owns the log
    # stream, then surface the captured aria2c/curl diagnostics.
    stop_poll
    echo "[fetch-ipfs] error: aria2c and fallback both failed for $cid" >&2
    [ -f "$TMPDIR/fetch.log" ] && cat "$TMPDIR/fetch.log" >&2
    exit 1
  '';
}
