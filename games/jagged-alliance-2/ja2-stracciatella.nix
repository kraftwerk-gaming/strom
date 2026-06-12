# Contained, buildable ja2-stracciatella for strom.
#
# nixpkgs' `ja2-stracciatella` is `meta.broken = true` (as of nixpkgs-unstable
# 2026-05, v0.21.0). Three blockers, all fixed here without touching nixpkgs:
#
#  1. CMake 4 dropped compatibility with `cmake_minimum_required(<3.5)`, which
#     the vendored string_theory / magic_enum builder sub-projects (and sol2
#     3.2.2 below) still declare. They run as *nested* CMake invocations
#     (ExternalProject / execute_process), so the top-level `-D` cache flag does
#     not reach them; we export `CMAKE_POLICY_VERSION_MINIMUM=3.5` into the
#     environment so every nested cmake inherits it.
#
#  2. With `LOCAL_MINIAUDIO_LIB=OFF`, stracciatella points `MINIAUDIO_INCLUDE_DIR`
#     at the nixpkgs `miniaudio` package, but that package ships only compiled
#     `.so` libs with no `miniaudio.h` (and no `extras/stb_vorbis.c`), so the
#     `dependencies/lib-miniaudio/CMakeLists.txt` header/version checks fail
#     ("miniaudio.h not found"). We point MINIAUDIO_INCLUDE_DIR at the exact
#     upstream miniaudio source tree stracciatella pins for its bundled build
#     (mackron/miniaudio @ 4dfe7c4…, a 0.11.x snapshot), which carries
#     `miniaudio.h` + `extras/stb_vorbis.c` and passes all three CMake checks.
#
#  3. nixpkgs supplies sol2 3.5.0, whose `usertype_container` iterator API
#     changed and no longer compiles stracciatella 0.21.0's
#     `ScriptingExtensionsLua.cc` ("...::iter has no member named 'end'").
#     Stracciatella pins sol2 v3.2.2 (its own getter). sol2 is header-only, so
#     we rebuild the nixpkgs sol2 derivation at the pinned 3.2.2 tag and inject
#     it as the build input.
{
  ja2-stracciatella,
  sol2,
  fetchFromGitHub,
  fetchzip,
}:
let
  # The miniaudio revision stracciatella's own getter pins
  # (dependencies/lib-miniaudio/getter/CMakeLists.txt.in). Header-only source
  # tree, used solely as an include dir at build time.
  miniaudioSrc = fetchzip {
    url = "https://github.com/mackron/miniaudio/archive/4dfe7c4c31df46e78d9a1cc0d2d6f1aef5a5d58c.zip";
    hash = "sha256-ATbMmSMV+XROwPR2Qwc5MbEJTFx9eIjbaypau7x2dEg=";
  };

  # sol2 at the version stracciatella 0.21.0 was written against
  # (dependencies/lib-sol2/getter pins v3.2.2). Header-only; only src changes.
  sol2_322 = sol2.overrideAttrs (old: {
    version = "3.2.2";
    src = fetchFromGitHub {
      owner = "ThePhD";
      repo = "sol2";
      rev = "v3.2.2";
      hash = "sha256-KWtVEURJTU97h3vEqALb6vkyyU9SvU4P1OIuG4nBBus=";
    };
    env = (old.env or { }) // {
      CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    };
  });
in
(ja2-stracciatella.override { sol2 = sol2_322; }).overrideAttrs (old: {
  meta = old.meta // {
    broken = false;
    # The SFI source-code license is unfree; strom's flake instantiates
    # nixpkgs without allowUnfree, so the package must opt itself in.
    license = old.meta.license // {
      free = true;
    };
  };

  # Inherited by nested string_theory / magic_enum cmake invocations.
  # NIX_CFLAGS_COMPILE: sol2 3.2.2 (2021) trips GCC 15's stricter two-phase
  # template name lookup (`-Wtemplate-body`, error by default: "class
  # sol::optional<T&> has no member named 'construct'"). The code is valid
  # under the looser pre-15 rules, so `-fpermissive` downgrades it to a warning.
  env = (old.env or { }) // {
    CMAKE_POLICY_VERSION_MINIMUM = "3.5";
    NIX_CFLAGS_COMPILE = "${old.env.NIX_CFLAGS_COMPILE or ""} -fpermissive";
  };

  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DMINIAUDIO_INCLUDE_DIR=${miniaudioSrc}"
  ];
})
