{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  runCommandLocal,
}:

let
  tenoke-unpack = runCommandLocal "tenoke-unpack"
    {
      nativeBuildInputs = [ pkgs.stdenv.cc ];
    }
    ''
      mkdir -p "$out/bin"
      $CC -O2 -Wall -Wextra -o "$out/bin/tenoke-unpack" ${./unpack.c}
    '';

  iso = fetchIpfs {
    cid = "QmWqBkpwEFhbVWmDttiBGn99oPTFwotA242en3nHKDzPYq";
    hash = "sha256-8ZjnDT+NOp2evDwgAPDHmp2HbQ6ap63gqXfMrX9P3DU=";
    name = "vampire-crawlers.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vampire-crawlers";

  src = iso;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"

    # Extract ISO contents
    cd /tmp
    mkdir -p iso_contents
    cd iso_contents && 7z x ${iso} -aoa && cd ..

    # Unpack SETUP.bin using the TENOKE unpacker
    ${tenoke-unpack}/bin/tenoke-unpack iso_contents/SETUP.exe iso_contents/SETUP.bin unpacked

    # Move game files to output
    cp -r "unpacked/Vampire Crawlers"/* "$out"/

    # Apply crack (replacement plugins)
    cp -r "iso_contents/Crack/Vampire Crawlers_Data"/* "$out/Vampire Crawlers_Data"/

    rm -rf iso_contents unpacked
  '';

  runtime = "proton";
  executable = "Vampire Crawlers.exe";

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

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    PULSE_LATENCY_MSEC = "60";
    DXVK_ASYNC = "1";
  };

  preRun = "";

  meta = {
    description = "Vampire Crawlers (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vampire-crawlers";
  };
}
