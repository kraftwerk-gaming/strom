# Build a minimal FHS userspace via pkgs.buildEnv. Returns binds for
# the outer bwrap call (no nested buildFHSEnv).
#
# `targetPkgs pkgs` is called once and partitioned by
# stdenv.hostPlatform.system so `p.pkgsi686Linux.foo` lands in fhs32
# and 64-bit entries in fhs64. Calling `targetPkgs pkgsi686Linux`
# directly would force i686 rebuilds of treewide packages — don't.
{
  lib,
  pkgs,
}:

{
  targetPkgs,
  multilib ? false,
  name ? "strom-fhs",
}:

let
  pkgs32 = pkgs.pkgsi686Linux;

  # glibc/locales/libstdc++ + a few unix CLI tools so /usr/bin/env,
  # /usr/bin/python3, tar/sed/grep work for shebangs and helper scripts.
  baseTargetPkgs = with pkgs; [
    glibc
    glibcLocales
    gcc-unwrapped.lib
    coreutils
    bashInteractive
    findutils
    gnused
    gnugrep
    gnutar
    gawk
    gzip
    xz
  ];
  baseTargetPkgs32 = with pkgs32; [
    glibc
    gcc-unwrapped.lib
  ];

  allPaths = targetPkgs pkgs;
  is32 = p: (p.stdenv.hostPlatform.system or "x86_64-linux") == "i686-linux";
  paths64 = lib.filter (p: !(is32 p)) allPaths;
  paths32 = lib.filter is32 allPaths;

  # Empty /lib32 placeholder so bwrap can mount fhs32 at /usr/lib32
  # after /usr has been ro-bound (otherwise it'd fail mkdir on ro fs).
  # Also drop a ld-linux.so.2 symlink into /lib so that 32-bit Wine exes
  # — which hardcode `/lib/ld-linux.so.2` as their ELF interpreter —
  # can resolve it (target /usr/lib32/ld-linux.so.2 becomes valid after
  # the runtime --ro-bind ${fhs32}/lib /usr/lib32 above). Matches what
  # nixpkgs' buildFHSEnv does in buildFHSEnv.nix.
  lib32Mountpoint = pkgs.runCommandLocal "${name}-lib32-mountpoint" { } ''
    mkdir -p $out/lib32 $out/lib
    ln -s /usr/lib32/ld-linux.so.2 $out/lib/ld-linux.so.2
  '';

  fhs64 = pkgs.buildEnv {
    name = "${name}-fhs64";
    paths = baseTargetPkgs ++ paths64 ++ lib.optionals multilib [ lib32Mountpoint ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/lib32"
      "/lib64"
      "/libexec"
      "/sbin"
      "/share"
      "/include"
    ];
    ignoreCollisions = true;
    extraOutputsToInstall = [
      "lib"
      "out"
      "bin"
    ];
  };

  fhs32 =
    if multilib then
      pkgs.buildEnv {
        name = "${name}-fhs32";
        paths = baseTargetPkgs32 ++ paths32;
        pathsToLink = [
          "/lib"
          "/libexec"
        ];
        ignoreCollisions = true;
        extraOutputsToInstall = [
          "lib"
          "out"
        ];
      }
    else
      null;

in
{
  inherit fhs64 fhs32;

  # Use --ro-bind (not --symlink) for /bin /lib /lib64: NixOS hosts
  # have real dirs at those paths from --ro-bind / /, and bwrap won't
  # --symlink over them. /sbin and /lib32 are skipped at the root
  # because the host lacks them and bwrap can't mkdir on the ro root.
  bwrapArgs = [
    "--ro-bind"
    "${fhs64}"
    "/usr"
    "--ro-bind"
    "${fhs64}/bin"
    "/bin"
    "--ro-bind"
    "${fhs64}/lib"
    "/lib"
    "--ro-bind"
    "${fhs64}/lib64"
    "/lib64"
  ]
  ++ lib.optionals multilib [
    "--ro-bind"
    "${fhs32}/lib"
    "/usr/lib32"
  ];

  # LD_LIBRARY_PATH so bare-soname dlopen reaches /usr/lib*. nixpkgs
  # glibc's default search hits ${glibc}/lib + /lib64 but not /usr/lib.
  env = {
    LD_LIBRARY_PATH = if multilib then "/usr/lib:/usr/lib64:/usr/lib32" else "/usr/lib:/usr/lib64";
  };
}
