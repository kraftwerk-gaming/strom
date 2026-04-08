{ pkgs, games }:

let
  inherit (pkgs) lib;

  entries = lib.concatLists (
    lib.mapAttrsToList (
      name: pkg:
      let
        sources = builtins.filter (s: (s.cid or "") != "") (pkg.passthru.ipfsSources or [ ]);
      in
      lib.imap0 (i: s: {
        name = if (s.name or "") != "" then "${name}/${s.name}" else "${name}/${name}-${toString i}";
        cid = s.cid;
      }) sources
    ) games
  );

  # Build a list of "ipfs files cp" lines, plus mkdir for any subdirs
  cpLines = lib.concatMapStringsSep "\n" (
    e:
    let
      parent = builtins.dirOf e.name;
      mkdirLine = if parent == "." then "" else ''ipfs files mkdir -p "/strom/${parent}" || true'';
      cpLine = ''ipfs files cp "/ipfs/${e.cid}" "/strom/${e.name}" 2>/dev/null || echo "cp failed: ${e.name} ${e.cid}" >&2'';
    in
    if mkdirLine == "" then cpLine else "${mkdirLine}\n${cpLine}"
  ) entries;

  remoteScript = pkgs.writeShellScript "strom-publish-remote" ''
    set -eu

    : "''${KEY_NAME:=strom}"
    : "''${IPFS_USER:=ipfs}"
    : "''${IPFS_PATH:=/var/lib/ipfs}"
    export IPFS_PATH

    ipfs() { sudo -H -u "$IPFS_USER" IPFS_PATH="$IPFS_PATH" -- ipfs "$@"; }

    if ! command -v sudo >/dev/null; then
      echo "error: sudo required on remote" >&2
      exit 1
    fi

    if ! sudo -u "$IPFS_USER" -- sh -c 'command -v ipfs' >/dev/null; then
      echo "error: ipfs not on PATH for user '$IPFS_USER'" >&2
      exit 1
    fi

    if ! ipfs key list | awk '{print $1}' | grep -qx "$KEY_NAME"; then
      echo "ipns key '$KEY_NAME' not present, generating it"
      gen_name=$(ipfs key gen --type=ed25519 "$KEY_NAME")
      echo "generated ipns name: $gen_name"
      echo "  -> set services.strom-ipfs-mirror.ipnsName = \"$gen_name\";"
    else
      existing=$(ipfs key list -l | awk -v n="$KEY_NAME" '$2 == n {print $1}')
      echo "using existing ipns key '$KEY_NAME' ($existing)"
    fi

    # Reset the MFS dir each run; MFS root pin keeps the directory block
    # alive without fetching any of the referenced child content.
    ipfs files rm -r /strom 2>/dev/null || true
    ipfs files mkdir -p /strom

    ${cpLines}

    root=$(ipfs files stat --hash /strom)
    echo "root CID: $root"

    echo "publishing /ipfs/$root under key '$KEY_NAME' (DHT publish, ~30s)"
    ipfs name publish --key="$KEY_NAME" --allow-offline "/ipfs/$root"
  '';
in
pkgs.writeShellApplication {
  name = "strom-publish-ipns";
  runtimeInputs = [
    pkgs.openssh
    pkgs.coreutils
  ];
  text = ''
    # Publish a /strom directory of all this flake's CIDs on a remote kubo
    # daemon and announce its current root via IPNS.
    #
    # Usage:
    #   strom-publish-ipns <ssh-target> [key-name]
    #
    # ssh-target is anything ssh accepts: "user@host", "host", or
    # "ssh://user@host:port".
    #
    # Environment overrides forwarded to the remote:
    #   STROM_IPFS_USER (default: ipfs)
    #   STROM_IPFS_PATH (default: /var/lib/ipfs)

    if [ $# -lt 1 ]; then
      echo "usage: strom-publish-ipns <ssh-target> [key-name]" >&2
      exit 1
    fi

    target="$1"
    key_name="''${2:-strom}"

    ssh "$target" \
      env KEY_NAME="$key_name" \
          IPFS_USER="''${STROM_IPFS_USER:-ipfs}" \
          IPFS_PATH="''${STROM_IPFS_PATH:-/var/lib/ipfs}" \
          bash -s < ${remoteScript}
  '';
}
