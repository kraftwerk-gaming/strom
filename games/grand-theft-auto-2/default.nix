{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Preinstalled, NT-kernel-patched freeware portable of GTA 2 (DMA Design
  # / Rockstar 1999). Rockstar released the PC build of GTA 2 as freeware
  # in 2004 and re-published it as "Rockstar Classics" in 2008. This
  # portable copy ships the GTA2/ tree (gta2.exe + gta2 manager.exe + data/
  # + gtaudio/) with an NT-kernel patch applied so the binary launches on
  # modern Windows. The portable shipped with stub silent gtaudio/*.wav files
  # to shrink the archive; music tarball below restores the real tracks.
  src = fetchIpfs {
    cid = "QmXf4yBiYYqCPc18buJCL4MtFiHDR5dNhVyfEhyVqSzYsy";
    fallbackUrl = "https://archive.org/download/gta2_portable/Grand%20Theft%20Auto%202%20%28with%20NT%20kernel%20patch%29.rar";
    hash = "sha256-AN1HyYF65DNYSyZh1IA35apgVCKdhqXvnTGlHVnJs48=";
    name = "grand-theft-auto-2-portable.rar";
  };

  # gtaudio/*.wav music tracks (radio + intermission), repacked from the
  # 2004 Rockstar Classics freeware release where Rockstar transcoded the
  # original .mp2 tracks to uncompressed PCM .wav. 23 files, ~299 MiB
  # uncompressed; the NT-kernel-patched gta2.exe reads these directly.
  music = fetchIpfs {
    cid = "QmdNYqtgqFPrJLToMyAfTBoyL2mcS9qhUR3Gp7Df3sSXLz";
    fallbackUrl = "https://archive.org/download/grand-theft-auto-2_202509/Grand%20Theft%20Auto%202.zip";
    hash = "sha256-JXUY7XrjfrrJWYyQcXx35TM1JPFmdNJ3cI2Qw8Ezj3E=";
    name = "grand-theft-auto-2-music.tar.xz";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "grand-theft-auto-2";

  inherit src;

  nativeBuildInputs = [ unar ];

  # Archive root holds a single GTA2/ directory containing gta2.exe,
  # gta2 manager.exe, the data/ and gtaudio/ subtrees and the bundled
  # DLLs (DMAGlide.dll, D3DPoly.dll, binkw32.dll, mss32.dll, ...).
  # Flatten it into $out so gta2.exe sits at the overlay root.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/GTA2/. "$out"/
    # Overlay the music tarball over the silent gtaudio/ stubs.
    chmod -R u+w "$out/gtaudio"
    tar xf ${music} -C "$out"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # player/plyslot*.dat next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  # gta2.exe is the actual game; "gta2 manager.exe" is the
  # configuration launcher which gamescope handles for us.
  executable = "gta2.exe";

  # CDMusicType=1 makes gta2.exe scan drive letters C: through Z: for a
  # `GTAUDIO\<n>.wav` track (the original CD-audio code path). Map D: to
  # $GAMEDIR so the drive scan resolves to $GAMEDIR/gtaudio/. Inject the
  # registry key directly into system.reg under Wow6432Node (the live
  # location on 64-bit wine prefixes); the shipped GTA2.REG sits at the
  # 64-bit path and isn't auto-imported.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    mkdir -p "$pfx/dosdevices"
    ln -snf "$GAMEDIR" "$pfx/dosdevices/d:"

    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -q 'CDMusicType' "$SYSREG"; then
      if grep -q 'DMA Design Ltd\\\\GTA2\\\\Sound' "$SYSREG"; then
        sed -i '/^\[Software\\\\Wow6432Node\\\\DMA Design Ltd\\\\GTA2\\\\Sound\] /a "CDMusicType"=dword:00000001' "$SYSREG"
      else
        printf '\n[Software\\\\Wow6432Node\\\\DMA Design Ltd\\\\GTA2\\\\Sound]\n"CDMusicType"=dword:00000001\n' >> "$SYSREG"
      fi
    fi
  '';

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
    description = "Grand Theft Auto 2 (DMA Design / Rockstar 1999, freeware, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "grand-theft-auto-2";
  };
}
