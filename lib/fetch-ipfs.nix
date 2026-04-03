# fetch-ipfs.nix - Fixed-output derivation fetcher that retrieves files
# from the IPFS DHT using ipget, with fallback URL.
#
# Fully standalone: ipget spawns a temporary IPFS node, fetches the
# CID via DHT/bitswap, and tears everything down automatically.
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
  ipget,
  curl,
  cacert,
}:

{
  cid,
  fallbackUrl ? "",
  hash,
  name,
}:

stdenvNoCC.mkDerivation {
  inherit name;

  nativeBuildInputs = [
    ipget
    curl
  ];

  outputHash = hash;
  outputHashMode = "flat";
  outputHashAlgo = "sha256";

  inherit cid fallbackUrl;

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  preferLocalBuild = true;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  buildCommand = ''
    echo "Fetching $cid from IPFS DHT..."

    if timeout 600 ipget -n temp --progress -o "$out" "$cid" 2>&1; then
      echo "Got $cid from IPFS"
      exit 0
    fi

    echo "IPFS fetch failed, trying fallback..."

    if [ -n "$fallbackUrl" ]; then
      echo "Downloading from $fallbackUrl"
      curl -fL --max-time 1800 --progress-bar \
        --retry 3 \
        -o "$out" \
        "$fallbackUrl"
      exit 0
    fi

    echo "error: IPFS fetch failed and no fallback URL for $cid"
    exit 1
  '';
}
