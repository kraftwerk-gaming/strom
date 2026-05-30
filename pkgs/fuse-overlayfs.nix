# fuse-overlayfs with copy-up fix for read-only lower layers (nix store).
#
# Kernel overlayfs (bwrap --overlay) preserves the nix-store lowers' 0555
# dir mode in the merged view and, in strom's single-uid userns, the store
# dirs map to the unmapped 65534 owner so CAP_DAC_OVERRIDE never applies.
# A subdir that exists only in a lower therefore stays unwritable and the
# engine can't create new files in it (no copy-up makes the parent dir
# writable on its own). This patched fuse-overlayfs runs the merge in
# userspace: with squash_to_uid every inode is presented as caller-owned,
# and the copy-up patch ORs in owner write/exec bits so copied-up dirs are
# writable -> write-anything-on-demand with ZERO predeclaration.
# https://github.com/containers/fuse-overlayfs/issues/377
{ pkgs }:

pkgs.fuse-overlayfs.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./fuse-overlayfs-copyup.patch ];
})
