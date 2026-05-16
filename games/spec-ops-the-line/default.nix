{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  unar,
  innoextract,
}:

let
  # GOG release of Spec Ops: The Line (Yager, 2012). The zip wraps the
  # GOG Inno setup tree: a self-extracting setup_*.exe plus two .bin
  # slices and a small hotfix patcher. innoextract --gog reassembles
  # the install tree (Binaries/, Engine/, SOTLGame/, ...). The engine
  # is UDK / Unreal Engine 3; SpecOpsTheLine.exe under Binaries/Win32
  # is the launcher executable.
  src = fetchIpfs {
    cid = "QmYK3WWJMfFCDBmJkrbWPnPkvTsVLb79UGQbfzv26Yr6ZL";
    fallbackUrl = "https://archive.org/download/spec-ops-the-line-gog/Spec%20Ops%20The%20Line%20%5BGOG%5D.zip";
    hash = "sha256-pzF0iOgnHhtqNe954/daJ0210zhWYyoo5IyQgxzwFhs=";
    name = "spec-ops-the-line-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "spec-ops-the-line";

  inherit src;

  nativeBuildInputs = [
    unzip
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/Spec Ops The Line [GOG]/setup_spec_ops_the_line_1.0.689_(26698).exe"
    # innoextract drops the game tree at the root of -d; app/ holds the
    # GOG icon + webcache + readme stubs we don't need.
    cp -r "$TMPDIR/iss"/. "$out"/
    rm -rf "$out/__redist" "$out/tmp" "$out/commonappdata" "$out/app"
  '';

  runtime = "proton";
  executable = "Binaries/Win32/SpecOpsTheLine.exe";

  # The GOG offline installer is single-language (this dump is the
  # Italian SKU per goggame-*.info), and the UE3 install ships *every*
  # locale UPK + Localization/<lang>/ tree under SRGame/. With no user
  # config telling UE3 which to use, it defaults to a non-English one
  # (Spanish in practice). The .ini files under SRGame/Config are
  # encrypted by Yager (open them and `file` reports "OpenPGP Public
  # Key"), so seeding Language=INT there is a non-starter. UE3 also
  # honours `-LANGUAGE=<code>` on the exe command line, which short-
  # circuits all of that and lands us in English.
  executableArgs = [ "-LANGUAGE=INT" ];

  # UE3 / SRGame writes its Config (UDKEngine.ini, SRInput.ini, etc.)
  # and SaveData under Documents\My Games\SpecOps-TheLine\SRGame\.
  saveLocations = [ "Documents/My Games/SpecOps-TheLine" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Spec Ops: The Line (2012 Yager, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "spec-ops-the-line";
  };
}
