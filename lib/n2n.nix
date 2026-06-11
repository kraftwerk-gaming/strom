# n2n wrapperModule (raw module source).
#
# Runs an n2n `edge` INSIDE the game's bwrap sandbox so the game's
# LAN/multiplayer traffic rides an n2n overlay. Enabled for every game
# by default; set `n2n.enable = false;` to opt a game out. Even when
# enabled, the edge starts ONLY at runtime when `$N2N_SUPERNODE` is set;
# if unset the launch flow is byte-for-byte the shared-host-net
# behavior (no netns, no edge).
#
# When active, the sandbox runs in its OWN net namespace
# (--unshare-net) and gets internet via slirp4netns started host-side
# (see lib/mk-game.nix): slirp gives the netns a NATed tap0 with a
# default route to the real network, so the in-sandbox edge can reach a
# possibly-public supernode. slirp4netns is used rather than pasta
# because pasta rewrites the UDP reply source and n2n rejects the
# supernode ACK.
#
# The community + key are hardcoded to "strom"/"strom" in the launcher
# fragment; the supernode address comes from $N2N_SUPERNODE (`ip:port`,
# or `host:port` — a hostname is resolved host-side into
# STROM_N2N_SUPERNODE_IP before launch, since the isolated netns has no
# DNS; see mk-game's bwrap.extraPreHook and n2n-edge-launcher.sh).
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  _class = "wrapper";

  options = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to wire the in-sandbox n2n edge into this game. On by
        default for every game; set false to opt a game out entirely.
        Even when true, the edge starts only at runtime if
        `$N2N_SUPERNODE` is set; otherwise n2n is skipped and the game
        keeps the shared-host-net behavior.
      '';
    };

    community = mkOption {
      type = types.str;
      default = "strom";
      description = ''
        n2n community name (edge `-c`). Also used as the key (`-k`).
      '';
    };

    defaultRoute = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Move the sandbox's default route onto the n2n edge0 interface
        (away from slirp's tap0). Enable per game for titles whose "host
        game" screen reports the default-gateway adapter's IP — e.g.
        Diablo II's TCP/IP mode — so they advertise the overlay address
        instead of slirp's. The game then has no general internet (LAN
        play needs none); the edge keeps reaching the supernode via a
        pinned route. Only takes effect when `$N2N_SUPERNODE` is set.
      '';
    };

    extraEdgeArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra raw `edge` arguments appended to the hardcoded invocation.
      '';
    };

    connectorPackage = mkOption {
      type = types.package;
      default = config.pkgs.slirp4netns;
      defaultText = lib.literalExpression "pkgs.slirp4netns";
      description = ''
        Host-side userspace network connector. slirp4netns wires the
        sandbox's private net namespace to the real network (tap0 +
        default route + NAT) so the in-ns edge can reach the supernode.
      '';
    };
  };

  config = {
    # `package` is the n2n package (provides the `edge` binary, read by
    # store path in mk-game's inner script). The edge runs inside the
    # inner command; slirp4netns runs in the host wrapper. This module
    # carries only typed options + packages, so `outputs.wrapper` is
    # unused.
    package = lib.mkDefault config.pkgs.n2n;
    binName = lib.mkDefault "edge";
  };
}
