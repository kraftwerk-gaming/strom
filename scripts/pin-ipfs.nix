{ pkgs, games }:

let
  inherit (pkgs) lib;

  # Collect CIDs from game packages via passthru.ipfsSources
  cidEntries = lib.concatLists (
    lib.mapAttrsToList (
      name: pkg:
      let
        sources = pkg.passthru.ipfsSources or [ ];
        cids = builtins.filter (c: c != "") (map (s: s.cid or "") sources);
      in
      map (cid: "${name} ${cid}") cids
    ) games
  );

  cidLines = lib.concatStringsSep "\n" cidEntries;
  validGames = lib.concatStringsSep "|" (builtins.attrNames games);
  validGamesList = lib.concatMapStringsSep "\n" (n: "  ${n}") (builtins.attrNames games);
in
pkgs.writeShellApplication {
  name = "pin-ipfs";
  runtimeInputs = [ pkgs.curl ];
  text = ''
    if [[ $# -lt 1 ]]; then
      echo "Usage: pin-ipfs <ipfs-api-url> [game...]" >&2
      exit 1
    fi

    API_URL="''${1%/}"
    shift

    for game in "$@"; do
      case "$game" in
        ${validGames}) ;;
        *)
          echo "error: game '$game' does not exist" >&2
          echo "available games:" >&2
          echo "${validGamesList}" >&2
          exit 1
          ;;
      esac
    done

    failed=0
    while IFS=' ' read -r game cid; do
      [[ -z "$game" ]] && continue

      if [[ $# -gt 0 ]]; then
        match=0
        for f in "$@"; do
          [[ "$game" == "$f" ]] && match=1 && break
        done
        [[ $match -eq 0 ]] && continue
      fi

      echo -n "pin: $game $cid ... "
      if curl -sf -X POST "$API_URL/api/v0/pin/add?arg=$cid" > /dev/null; then
        echo "ok"
      else
        echo "FAILED"
        failed=1
      fi
    done <<< "${cidLines}"

    exit $failed
  '';
}
