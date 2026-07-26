{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Soulcalibur, the Sega Dreamcast release (Namco 1999) -- the canonical
  # home version, an arcade-perfect port that added the single-player
  # "Mission Battle" mode. Run via RetroArch + Flycast.
  #
  # Source is the Redump dump of the US retail GD-ROM (item "[Redump] Sega
  # Dreamcast", a complete 1454/1454 set). Verified English: the IP.BIN
  # header at the head of track 3 carries area symbol "U" (USA only -- the
  # Japan and Europe slots are blank) and product number T1401N, Namco
  # Hometek's North American serial; 1ST_READ.BIN is full of English UI
  # text ("MISSION BATTLE", "BATTLE THEATER", "Arcade version of
  # SOULCALIBUR."). This replaces an RGR-group rip that turned out to be a
  # Russian translation.
  #
  # Redump ships Dreamcast dumps as cue/bin rather than GDI: two tracks in
  # the single-density area and the GD area as track 3. Flycast's cue
  # parser understands that layout -- `REM HIGH-DENSITY AREA` switches it
  # to GD-ROM mode and pins track 3 at FAD 45150, which is exactly where
  # this dump's 504150 raw sectors start. Flycast boots Dreamcast titles
  # with its built-in HLE BIOS, so no dc_boot.bin is required.
  scArchive = fetchIpfs {
    cid = "Qmbi1qZhNwE6cdMTXgkLwLVoCS4rGPbvNrufV3GnLtzY2D";
    fallbackUrl = "https://archive.org/download/rd-se-dc/Soulcalibur%20%28USA%29.7z";
    hash = "sha256-801cijzq7MubddI4Oi+QXFTuICp7EkSjKbh/yMYYr4I=";
    name = "soul-calibur.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "soul-calibur";
  src = scArchive;
  ipfsSources = [ scArchive ];

  nativeBuildInputs = [ pkgs.p7zip ];
  buildScript = ''
    mkdir -p $out
    # The three .bin tracks and the .cue sit at the archive root with no
    # directory prefix, so a plain extract leaves them side by side in
    # $out; Flycast resolves the cue's FILE entries relative to the cue.
    7z x "$src" -o"$out" -aoa
  '';

  runtime = "retroarch";
  executable = "Soulcalibur (USA).cue";

  retroarch = {
    cores = [ pkgs.libretro.flycast ];
    settings = {
      input_player1_up = "up";
      input_player1_down = "down";
      input_player1_left = "left";
      input_player1_right = "right";
      input_player1_a = "x";
      input_player1_b = "z";
      input_player1_x = "s";
      input_player1_y = "a";
      input_player1_l = "q";
      input_player1_r = "e";
      input_player1_start = "enter";
      input_player1_select = "rshift";
    };
  };

  meta = {
    description = "Soulcalibur (Dreamcast 1999 Namco, USA, via RetroArch / Flycast)";
    mainProgram = "soul-calibur";
    platforms = [ "x86_64-linux" ];
  };
}
