# fetch-ipfs.nix - Fixed-output derivation fetcher that retrieves a CID
# from one or more HTTP IPFS gateways using aria2c. aria2c parallelises
# the download as Range requests across the given gateways, so a single
# slow / mid-stream-cutting gateway can't stall the build the way a
# CAR-streaming retriever does. Cloudflare-fronted public gateways tend
# to truncate long streamed responses; aria2c sidesteps this because each
# connection is a short, cacheable Range.
#
# Usage, one file:
#   fetchIpfs {
#     cid = "QmXxx...";
#     fallbackUrl = "https://archive.org/download/...";
#     hash = "sha256-...";
#     name = "foo.zip";
#   }
#
# Usage, a directory (a game's built tree, pinned once and fetched as-is
# by the desktop and the Android client alike):
#   fetchIpfs {
#     cid = "bafybei...";
#     directory = true;
#     hash = "sha256-...";   # `nix hash path` of the tree (NAR hash)
#     name = "foo-tree";
#     size = 3887109121;     # optional: uncompressed bytes, for the phone
#     manifest = "bafkrei..."; # optional: the pinned listing sidecar
#   }
#
# A directory with no `manifest` is walked one block at a time through
# the gateways (`?format=car&dag-scope=block`, the one directory request
# every public gateway answers; see ipfs-walk.py), then every file is
# downloaded by path with the same multi-gateway aria2c Range racing as
# a single file. The walk costs one small request per entry, which is
# what public gateways rate-limit on, so a pinned tree SHOULD also pin
# its listing (lib/tree-manifest.py over the built tree, the same file
# ipfs-walk.py would produce) and name it here as `manifest`: one small
# fetch then replaces the whole walk. A wrong or stale manifest cannot
# corrupt anything -- it only names files; the NAR outputHash still
# gates the content -- it can only fail the build.
# There is no fallbackUrl for a tree: nothing outside IPFS serves it.
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
  python3,
}:

{
  cid,
  fallbackUrl ? "",
  hash,
  name,
  directory ? false,
  # Uncompressed bytes of a directory, recorded when it is pinned, so a
  # client can show "n of total" before and while fetching. Null when
  # unmeasured; nothing here depends on it.
  size ? null,
  # CID of the pinned listing sidecar (see above). Null: walk the DAG.
  manifest ? null,
  # HTTP gateway prefixes (no trailing slash, no /ipfs/). aria2c will
  # request "<prefix>/ipfs/<cid>" from each and split the file across them
  # via Range. Order is measured, not alphabetical: against a freshly
  # pinned CID with one DHT provider, pinata and nftstorage.link resolve it
  # cold, while ipfs.io, dweb.link and w3s.link answer 504 after their
  # ~28 s budget until something has warmed their cache -- and then they
  # are the fastest. aria2c races all of them for a file; the directory
  # walk asks them in this order, one request at a time, so the ones that
  # find content cold go first. trustless-gateway.link is omitted because
  # it returns 406 without an explicit `Accept: application/vnd.ipld.car`
  # header and serves CARs rather than raw bytes.
  providers ? [
    "https://gateway.pinata.cloud"
    "https://nftstorage.link"
    "https://ipfs.io"
    "https://dweb.link"
    "https://w3s.link"
  ],
}:

assert lib.assertMsg (
  !directory || fallbackUrl == ""
) "fetchIpfs: a directory has no fallbackUrl; nothing outside IPFS serves a tree";

stdenvNoCC.mkDerivation {
  inherit name;

  nativeBuildInputs = [
    aria2
    curl
  ]
  ++ lib.optional directory python3;

  outputHash = hash;
  outputHashMode = if directory then "recursive" else "flat";
  outputHashAlgo = "sha256";

  inherit cid fallbackUrl;
  fetchDirectory = lib.boolToString directory;
  manifestCid = lib.optionalString (manifest != null) manifest;
  providers = lib.concatStringsSep " " providers;
  walker = ./ipfs-walk.py;

  # What a recipe and the Android manifest read off the derivation: the
  # CID it fetches, whether that is a tree, the tree's size, and its
  # pinned listing sidecar.
  passthru = {
    inherit
      cid
      directory
      size
      manifest
      ;
  };

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  preferLocalBuild = true;

  # STROM_IPFS_GATEWAYS lets the invoking user inject extra (private/local)
  # gateways without baking their URL into the repo. Format: comma- or
  # space-separated prefixes, e.g. "https://my.gateway https://other.gw".
  impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [ "STROM_IPFS_GATEWAYS" ];

  buildCommand = ''
    # Assemble the gateway list: user-injected gateways first (preferred
    # when reachable), then the public defaults. aria2c races them via
    # Range requests, so the local mirror dominates when it's fast and the
    # public ones serve as automatic failover.
    gws=""
    if [ -n "''${STROM_IPFS_GATEWAYS:-}" ]; then
      for gw in $(echo "$STROM_IPFS_GATEWAYS" | tr ',' ' '); do
        [ -n "$gw" ] && gws="$gws ''${gw%/}"
      done
    fi
    for gw in $providers; do
      gws="$gws ''${gw%/}"
    done
    urls=""
    for gw in $gws; do
      urls="$urls $gw/ipfs/$cid"
    done

    echo "[fetch-ipfs] $cid via aria2c across:"
    for u in $urls; do echo "  $u"; done

    # --- structured download progress -----------------------------------
    # Emit "@nix {...}" JSON log lines so the Nix daemon renders this FOD
    # in the aggregate "X MiB DL" progress bar, exactly like a native
    # fetchurl. The daemon parses builder stderr untrusted, which means it
    # only admits actFileTransfer (101) activities (see Nix's
    # handleJSONLogMessage); that is precisely the download case, so we
    # open one such activity and report bytes by polling the output
    # size. Polling the output (rather than scraping aria2c's stdout)
    # works identically for the curl fallback and survives aria2c
    # log-format changes. Field/level values mirror
    # libstore/filetransfer.cc.
    #
    # The daemon parses the build log line by line; a "@nix {...}" line is
    # only recognised when it arrives intact (it must start with "@nix "
    # and parse as JSON). So once the poller starts, it must be the *sole*
    # writer to the log stream -- otherwise aria2c's concurrent stderr
    # interleaves mid-line and the structured tick is silently dropped.
    # We therefore funnel aria2c/curl chatter to a file and only surface
    # it on total failure.
    act_id=1
    nix_emit() { printf '@nix %s\n' "$1" >&2; }

    expected=0

    # Bytes fetched so far. A single file is written by aria2c as Range
    # segments at their own offsets, so report *allocated* blocks
    # (st_blocks, always 512-byte units), not st_size: with a sparse file
    # st_size jumps to the full length the moment the last segment is
    # seeked, whereas st_blocks counts only bytes actually written.
    # --file-allocation=none keeps the file sparse for this to hold; the
    # curl fallback writes sequentially, where it holds too. A tree is
    # many files, most of them written whole, so its allocated total is
    # the same measure summed.
    progress_cur() {
      if [ "$fetchDirectory" = true ]; then
        du -sB1 "$TMPDIR/tree" 2>/dev/null | cut -f1 || echo 0
      elif [ -f "$TMPDIR/fetch.bin" ]; then
        blocks=$(stat -c %b "$TMPDIR/fetch.bin" 2>/dev/null || echo 0)
        echo $((blocks * 512))
      else
        echo 0
      fi
    }

    progress_poll() {
      while :; do
        cur=$(progress_cur)
        if [ "$expected" -gt 0 ] && [ "$cur" -gt "$expected" ]; then
          cur=$expected
        fi
        nix_emit "{\"action\":\"result\",\"id\":$act_id,\"type\":105,\"fields\":[$cur,$expected,0,0]}"
        sleep 1
      done
    }

    start_progress() {
      nix_emit "{\"action\":\"start\",\"id\":$act_id,\"level\":4,\"type\":101,\"text\":\"fetching $cid\",\"fields\":[\"ipfs://$cid\"]}"
      if [ "$expected" -gt 0 ]; then
        nix_emit "{\"action\":\"result\",\"id\":$act_id,\"type\":106,\"fields\":[101,$expected]}"
      fi
      progress_poll &
      poll_pid=$!
    }

    # Idempotent: called on every success path before the mv (so the bar
    # doesn't flash back to 0 once the output is moved away) and once more
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

    # aria2c flags shared by both shapes.
    # --split / --max-connection-per-server control parallelism.
    # --min-split-size keeps Range chunks large enough that overhead
    # stays low; 16M is the aria2 default minimum that's also kind to
    # gateway caches.
    # --check-integrity=false: integrity is verified by Nix's outputHash.
    # --continue / --allow-overwrite cope with restarted builds.
    # --lowest-speed-limit closes any connection delivering <=10KB/s;
    # without it aria2 keeps accepted-but-stalled gateway sockets
    # open indefinitely. The outer `timeout 3600` is a hard ceiling
    # so even pathological all-stalled state falls through to the
    # curl/fallbackUrl path instead of hanging the build forever.
    aria() {
      timeout 3600 aria2c \
        --console-log-level=warn \
        --summary-interval=10 \
        --connect-timeout=30 \
        --timeout=120 \
        --lowest-speed-limit=10K \
        --max-tries=5 \
        --retry-wait=10 \
        --max-connection-per-server=4 \
        --min-split-size=16M \
        --file-allocation=none \
        --check-integrity=false \
        --continue=true \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        "$@" >>"$TMPDIR/fetch.log" 2>&1
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
    aria_retrying() {
      attempt=1
      while [ "$attempt" -le 3 ]; do
        if aria "$@"; then
          return 0
        fi
        echo "[fetch-ipfs] aria2c attempt $attempt failed; resuming" >>"$TMPDIR/fetch.log"
        attempt=$((attempt + 1))
      done
      return 1
    }

    fail() {
      # Stop the poller first so it no longer owns the log stream, then
      # surface the captured diagnostics.
      stop_poll
      echo "[fetch-ipfs] error: $1" >&2
      [ -f "$TMPDIR/fetch.log" ] && cat "$TMPDIR/fetch.log" >&2
      exit 1
    }

    # --- a directory ------------------------------------------------------
    if [ "$fetchDirectory" = true ]; then
      # Enumerate first: the listing yields every file's size, so the bar
      # has its denominator before a byte of payload moves. With a pinned
      # manifest that is one small fetch; without one the DAG is walked,
      # one gateway request per entry (the request count is what public
      # gateways rate-limit on, so pin a manifest for anything big).
      if [ -n "$manifestCid" ]; then
        got=""
        for round in 1 2 3 4 5; do
          for gw in $gws; do
            if curl -fsSL --connect-timeout 30 --max-time 120 \
              "$gw/ipfs/$manifestCid?filename=x.bin&download=true" \
              -o "$TMPDIR/listing" 2>>"$TMPDIR/fetch.log"; then
              # A rate-limit or error page instead of the listing would
              # steer every later request wrong; the format check catches
              # it here. (Content is still gated by the NAR hash.)
              if awk -F'\t' '
                  $1 == "d" && NF == 2 { next }
                  $1 == "f" && NF == 5 { next }
                  { exit 1 }
                ' "$TMPDIR/listing" && [ -s "$TMPDIR/listing" ]; then
                got=1
                break 2
              fi
              echo "[fetch-ipfs] $gw served a malformed manifest $manifestCid" >>"$TMPDIR/fetch.log"
            fi
          done
          sleep $((round * 15))
        done
        [ -n "$got" ] || fail "no gateway served the manifest $manifestCid"
      else
        python3 "$walker" "$cid" "$TMPDIR/listing" $gws 2>>"$TMPDIR/fetch.log" \
          || fail "could not walk $cid"
      fi
      expected=$(awk -F'\t' '$1 == "f" { s += $2 } END { print s + 0 }' "$TMPDIR/listing")
      echo "[fetch-ipfs] $cid: $(grep -c '^f' "$TMPDIR/listing") files, $expected bytes"

      mkdir -p "$TMPDIR/tree"
      # Directories, including empty ones, and empty files, which aria2c
      # has nothing to fetch for.
      awk -F'\t' -v tree="$TMPDIR/tree" '
        $1 == "d" { system("mkdir -p \"" tree "/" $2 "\"") }
        $1 == "f" && $2 == 0 { system(": > \"" tree "/" $5 "\"") }
      ' "$TMPDIR/listing"

      # The files still missing or short: the input of the next round.
      # A file that arrived whole is never asked for again, so a gateway
      # that throttles part of a round costs a pause, not a restart. A
      # gateway can also answer 200 with something that is not the file
      # (a rate-limit page); the size check catches that here, and the
      # NAR hash would catch anything subtler.
      pending() {
        while IFS=$'\t' read -r want x quoted path; do
          got=$(stat -c %s "$TMPDIR/tree/$path" 2>/dev/null || echo -1)
          if [ "$got" != "$want" ]; then
            printf '%s\t%s\t%s\n' "$want" "$quoted" "$path"
          fi
        done < <(awk -F'\t' '$1 == "f" && $2 > 0 { print $2 "\t" $3 "\t" $4 "\t" $5 }' "$TMPDIR/listing")
      }

      # One aria2c input entry per pending file: every gateway's URL for
      # the path, then where to put it.
      #
      # `?filename=x.bin&download=true` makes the gateway answer
      # `application/octet-stream` + attachment instead of a sniffed
      # `text/html`. Cloudflare fronts several public gateways and
      # REWRITES text/html bodies in transit -- measured on ipfs.io: a
      # 2331-byte .htm from this repo's own pinned tree arrived as 2625
      # bytes with a hidden `/cdn-cgi/content?id=...` bot-check anchor
      # injected after <body>, which made the size check refuse the file
      # on all 8 rounds. Bytes are identical again with the
      # octet-stream disposition. The manifest fetch above wears the
      # same disguise.
      aria_input() {
        awk -F'\t' -v tree="$TMPDIR/tree" -v gws="$gws" -v cid="$cid" '
          BEGIN { n = split(gws, gw, " ") }
          {
            path = $3
            quoted = $2
            dir = tree
            base = path
            if (match(path, /\/[^\/]*$/)) {
              dir = tree "/" substr(path, 1, RSTART - 1)
              base = substr(path, RSTART + 1)
            }
            line = ""
            for (i = 1; i <= n; i++) {
              line = line (i > 1 ? "\t" : "") gw[i] "/ipfs/" cid "/" quoted "?filename=x.bin&download=true"
            }
            print line
            print " dir=" dir
            print " out=" base
          }
        '
      }

      start_progress
      # Public gateways rate-limit by request count, not bytes, and a tree
      # is many small requests: measured, 173 files asked for with 8
      # concurrent downloads and 4 connections per server drew 429 from
      # every gateway at once. So: one connection per server, a few files
      # at a time (Range splitting still applies to files above 64 MB),
      # and rounds with a growing pause for whatever a gateway refused.
      round=1
      while :; do
        pending >"$TMPDIR/pending"
        [ -s "$TMPDIR/pending" ] || break
        if [ "$round" -gt 8 ]; then
          fail "$(wc -l <"$TMPDIR/pending") files of $cid still missing after $((round - 1)) rounds"
        fi
        if [ "$round" -gt 1 ]; then
          echo "[fetch-ipfs] round $round: $(wc -l <"$TMPDIR/pending") files left" >>"$TMPDIR/fetch.log"
          sleep $((round * 15))
        fi
        aria_input <"$TMPDIR/pending" >"$TMPDIR/aria2.in"
        # --allow-overwrite: a short file from an earlier round with no
        # aria2 control file left to resume from is fetched afresh.
        aria --input-file="$TMPDIR/aria2.in" --max-concurrent-downloads=4 \
          --max-connection-per-server=1 --split=4 --max-tries=2 \
          --allow-overwrite=true || true
        round=$((round + 1))
      done

      while IFS=$'\t' read -r x path; do
        if [ "$x" = 1 ]; then
          chmod +x "$TMPDIR/tree/$path"
        fi
      done < <(awk -F'\t' '$1 == "f" { print $3 "\t" $5 }' "$TMPDIR/listing")

      stop_poll
      mv "$TMPDIR/tree" "$out"
      exit 0
    fi

    # --- a single file ----------------------------------------------------
    # Probe a gateway for the total size so the bar shows a percentage.
    # Optional: if no gateway yields a Content-Length the bar just counts
    # bytes up without a denominator. The `|| true` is what KEEPS it
    # optional: the builder runs under `set -e -o pipefail`, so without it
    # a gateway that fails the HEAD (ipfs.io answers 429 under load,
    # observed 2026-09-06 from four of the five defaults at once) makes
    # curl's exit 22 kill the whole derivation right here -- before
    # aria2c, before the retry loop, before the fallbackUrl, with nothing
    # in the log but the URL list.
    for u in $urls; do
      len=$(curl -fsSL -I --max-time 20 "$u" 2>/dev/null \
        | tr -d '\r' \
        | awk 'tolower($1) == "content-length:" { print $2 }' \
        | tail -n1 || true)
      case "$len" in
        "" | *[!0-9]*) ;;
        *)
          expected=$len
          break
          ;;
      esac
    done

    start_progress

    fetch_via_curl() {
      [ -z "$fallbackUrl" ] && return 1
      echo "[fetch-ipfs] fallback: $fallbackUrl" >>"$TMPDIR/fetch.log"
      # No --progress-bar: our poller owns the log stream; curl's progress
      # would interleave with it and corrupt structured ticks.
      curl -fL --max-time 1800 --retry 3 \
        -o "$TMPDIR/fetch.bin" "$fallbackUrl" >>"$TMPDIR/fetch.log" 2>&1
    }

    if aria_retrying --split=8 --dir="$TMPDIR" --out="fetch.bin" $urls; then
      stop_poll
      mv "$TMPDIR/fetch.bin" "$out"
      exit 0
    fi

    if fetch_via_curl; then
      stop_poll
      mv "$TMPDIR/fetch.bin" "$out"
      exit 0
    fi

    fail "aria2c and fallback both failed for $cid"
  '';
}
