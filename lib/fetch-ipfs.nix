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

  buildCommand = ''
    car_file="$TMPDIR/fetch.car"

    fetch_via_lassie() {
      echo "fetching $cid via lassie (providers: $providers + IPNI)"
      if lassie fetch \
        --progress \
        --providers "$providers" \
        --provider-timeout 60s \
        --global-timeout 1800s \
        --output "$car_file" \
        "$cid"
      then
        echo "extracting $cid from CAR"
        if car extract -f "$car_file" - > "$out"; then
          return 0
        fi
        echo "car extract failed" >&2
      fi
      rm -f "$car_file" "$out"
      return 1
    }

    fetch_via_curl() {
      [ -z "$fallbackUrl" ] && return 1
      echo "fetching fallback $fallbackUrl"
      curl -fL --max-time 1800 --progress-bar --retry 3 -o "$out" "$fallbackUrl"
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
