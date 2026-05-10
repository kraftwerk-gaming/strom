{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Europe PS2 release of MGS2 Substance (5-language: En/Fr/De/Es/It).
  # The PC port is broken on modern Wine (see archived attempt — engine
  # null-derefs in IDirectMusicLoader during init), so emulate the PS2
  # version via PCSX2 instead. Substance has all the VR missions and
  # Snake Tales the PC port also includes.
  gameSrc = fetchIpfs {
    cid = "QmbFSXqTsafRjxc5swkc1DkpLXRGBRkhjiNDsd5abyGsJC";
    fallbackUrl = "https://archive.org/download/metal-gear-solid-2-substance-europe-en-fr-de-es-it.iso/Metal%20Gear%20Solid%202%20-%20Substance%20%28Europe%29%20%28En%2CFr%2CDe%2CEs%2CIt%29.iso.zip";
    hash = "sha256-oY//d5O3kzlBQU2JTwTqncP4zmkJsjvnW8F+a0neumI=";
    name = "mgs2-substance-ps2-europe.iso.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "metal-gear-solid-2-substance";
  src = gameSrc;

  nativeBuildInputs = [
    pkgs.unzip
    pkgs.gzip
  ];
  # Archive ships zip-of-gzip-of-iso. Unzip yields ".iso.gz", gunzip
  # strips the .gz to give the raw PS2 disc image PCSX2 wants.
  buildScript = ''
    mkdir -p $out
    unzip "$src" -d $out
    gunzip "$out"/*.iso.gz
  '';

  runtime = "pcsx2";
  executable = "Metal Gear Solid 2 - Substance (Europe) (En,Fr,De,Es,It).iso";

  meta = {
    description = "Metal Gear Solid 2: Substance (PS2 Europe, via PCSX2)";
    mainProgram = "metal-gear-solid-2-substance";
    platforms = [ "x86_64-linux" ];
  };
}
