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

    fetch_via_aria() {
      # --split / --max-connection-per-server control parallelism.
      # --min-split-size keeps Range chunks large enough that overhead
      # stays low; 16M is the aria2 default minimum that's also kind to
      # gateway caches.
      # --check-integrity=false: integrity is verified by Nix's outputHash.
      # --conditional-get / --allow-overwrite=true cope with restarted builds.
      aria2c \
        --console-log-level=warn \
        --summary-interval=10 \
        --connect-timeout=30 \
        --timeout=120 \
        --max-tries=5 \
        --retry-wait=10 \
        --split=8 \
        --max-connection-per-server=4 \
        --min-split-size=16M \
        --check-integrity=false \
        --allow-overwrite=true \
        --auto-file-renaming=false \
        --dir="$TMPDIR" \
        --out="fetch.bin" \
        $urls
    }

    fetch_via_curl() {
      [ -z "$fallbackUrl" ] && return 1
      echo "[fetch-ipfs] fallback: $fallbackUrl"
      curl -fL --max-time 1800 --progress-bar --retry 3 \
        -o "$TMPDIR/fetch.bin" "$fallbackUrl"
    }

    if fetch_via_aria; then
      mv "$TMPDIR/fetch.bin" "$out"
      exit 0
    fi

    if fetch_via_curl; then
      mv "$TMPDIR/fetch.bin" "$out"
      exit 0
    fi

    echo "[fetch-ipfs] error: aria2c and fallback both failed for $cid" >&2
    exit 1
  '';
}
