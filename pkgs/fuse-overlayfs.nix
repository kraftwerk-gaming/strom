# fuse-overlayfs with copy-up fix for read-only lower layers (nix store).
# https://github.com/containers/fuse-overlayfs/issues/377
{ pkgs }:

pkgs.fuse-overlayfs.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./fuse-overlayfs-copyup.patch ];
})
