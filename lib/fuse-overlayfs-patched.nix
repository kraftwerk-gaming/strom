# Patched fuse-overlayfs that enables proper copy-up from read-only
# lower layers (like the Nix store where files are 444 and dirs 555).
#
# Upstream issues:
#   https://github.com/containers/fuse-overlayfs/issues/377
#   https://github.com/containers/fuse-overlayfs/issues/428
#
# Two patches:
# 1. rpl_stat: report writable permissions when squash_to_uid is active,
#    so the kernel (default_permissions) allows writes that trigger copy-up.
# 2. create_node_directory: add owner write+execute to copied-up dirs
#    (matching what copyup() already does for files with euid > 0).
{ pkgs }:

pkgs.fuse-overlayfs.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
        # 1. In rpl_stat: after uid/gid mapping, grant owner write permission
        sed -i '/st->st_gid = find_mapping/a\
    \
      /* Grant owner write permission when squash is active, enabling copy-up */\
      if (data->squash_to_uid != -1 || data->squash_to_root)\
        st->st_mode |= S_IWUSR | (S_ISDIR (st->st_mode) ? S_IXUSR : 0);' main.c

        # 2. In create_node_directory: add write perm to copied-up dirs for non-root
        sed -i '/ret = create_directory (lo, get_upper_layer (lo)->fd, src->path, times, src->parent, src->layer, sfd, st.st_uid, st.st_gid, st.st_mode, false, NULL);/s/st.st_mode/st.st_mode | (lo->euid > 0 ? 0700 : 0)/' main.c
  '';
})
