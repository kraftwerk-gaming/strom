{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchzip,
  p7zip,
  pkgsCross,
  runCommandLocal,
}:

let

  # ASI mod that fixes AB-BA deadlock on CS@00864F00 during track loading.
  deadlockFix =
    runCommandLocal "need-for-speed-underground-2-deadlock-fix"
      {
        nativeBuildInputs = [ pkgsCross.mingw32.buildPackages.gcc ];
      }
      ''
        mkdir -p "$out"
        i686-w64-mingw32-gcc -shared -o "$out/DeadlockFix.asi" ${./deadlock-fix.c} \
          -nostdlib -lkernel32 -Wl,--enable-stdcall-fixup,-e,__DllMainCRTStartup
      '';

  # ECM (External Custom Music) by VelocityCL/Drgn. ASI plugin that adds a
  # custom-music player to NFSU2 (NFSU2 itself has no scan-a-folder feature).
  # Reads `playlist`-named subfolder of its INI (default: "Music") next to
  # the ASI for wav/mp1/mp2/mp3/ogg/aif tracks. F11 toggles the in-game
  # overlay (volume + skip + playlist).
  ecm = fetchzip {
    url = "https://github.com/VelocityCL/ecm/releases/download/v0.4.0-alpha/Release-Win-x86.zip";
    hash = "sha256-+FbOZH6dTXSEcoMNJ+5/44rlH3rMCOeblZIEs8EMUF8=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  imports = [
    (
      { config, lib, ... }:
      let
        inherit (lib) mkOption types;
      in
      {
        options = {
          enablePlayerSoundtracks = mkOption {
            type = types.bool;
            default = false;
            description = ''
              When true, the launcher symlinks every file under
              `~/.strom/need-for-speed-underground-2/music/` into the
              overlay's `SCRIPTS/Music/` folder on each launch. ECM
              (External Custom Music, bundled as an ASI plugin) scans
              that folder and plays tracks via its in-game F11 overlay.
              The host directory is created on first launch; drop
              wav/mp1/mp2/mp3/ogg/aif files into it with no rebuild
              required.

              Note: symlink basenames are sanitized to 7-bit ASCII
              (`A-Za-z0-9 ._()[]-`) before being placed in `Music/`.
              ECM's `std::filesystem` enumeration crashes on filenames
              containing kanji or unicode punctuation, so non-ASCII
              bytes are stripped and collisions resolved by prepending
              a sha256 prefix. The original file in `~/.strom/.../music/`
              is untouched; only the in-overlay symlink name changes.
            '';
          };

          extraSoundtracks = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = ''
              Audio derivations to install at build time. Every regular
              file found under each derivation (recursive) is symlinked
              into the overlay's `SCRIPTS/Music/` folder by basename,
              where ECM picks them up. Supported formats per ECM:
              wav, mp1, mp2, mp3, ogg, aif. Typical sources are
              `pkgs.fetchurl` for individual tracks or a `runCommand`
              that transcodes a directory of source files.

              Note: symlink basenames are sanitized to 7-bit ASCII
              (`A-Za-z0-9 ._()[]-`) before being placed in `Music/`.
              ECM's `std::filesystem` enumeration crashes on filenames
              containing kanji or unicode punctuation, so non-ASCII
              bytes are stripped and collisions resolved by prepending
              a sha256 prefix. The derivation contents are unchanged;
              only the in-overlay symlink name differs from the source.
            '';
          };
        };

        config = {
          name = "need-for-speed-underground-2";

          src = fetchIpfs {
            cid = "QmTuALyoKP6Rsi3hboj2tip7skCa5hK2bg3MbpyJTRGXBm";
            fallbackUrl = "https://archive.org/download/NFSU2Stable/Need%20for%20Speed%20Underground%202.7z";
            hash = "sha256-aC+1gcJLFay2jWTDBOXZSL3tIxaBoDHV1amtl82XBlA=";
            name = "nfsu2.7z";
          };

          nativeBuildInputs = [ p7zip ];

          buildScript = ''
            mkdir -p "$out"
            7z x $src -o"$out"

            if [ -d "$out/Need for Speed Underground 2" ]; then
              mv "$out/Need for Speed Underground 2"/* "$out"/
              rmdir "$out/Need for Speed Underground 2"
            fi

            # Patch serial port Sleep(0) spinloops in SPEED2.EXE
            chmod u+w "$out/SPEED2.EXE"
            for offset in \
              0x35772b 0x35774a \
              0x35098d 0x350a0a 0x350f5c 0x350f8f \
              0x3571ee 0x3578cc 0x357d61 0x357d7b 0x357fdc \
              0x1fa3a4 0x243ce5 0x243d45 0x2d8891 0x2da440 0x34a15f; do
              printf '\x90\x90' | dd of="$out/SPEED2.EXE" bs=1 seek=$(($offset)) conv=notrunc 2>/dev/null
            done
            chmod u-w "$out/SPEED2.EXE"


            # Install deadlock fix ASI mod
            cp ${deadlockFix}/DeadlockFix.asi "$out/SCRIPTS/DeadlockFix.asi"

            ${lib.optionalString (config.enablePlayerSoundtracks || config.extraSoundtracks != [ ]) ''
              # Install ECM (external custom music) ASI + bass.dll + INI.
              # The release zip ships them under `scripts/` but fetchzip
              # strips that root; we drop the files into `SCRIPTS/`
              # alongside the other ASI mods loaded by dinput8.dll. ECM
              # reads the `playlist` dir from its INI relative to the
              # ASI; default `playlist = "Music"` -> `SCRIPTS/Music/`,
              # populated at launch by preRun (build-time + runtime
              # tracks).
              cp ${ecm}/ecm.x86.asi "$out/SCRIPTS/"
              cp ${ecm}/ecm.x86.ini "$out/SCRIPTS/"
              cp ${ecm}/bass.dll    "$out/SCRIPTS/"
            ''}
          '';

          # SPEED2.EXE must be a copy - game resolves its path through symlinks
          # and uses it as the base directory for saves/configs
          # EXE and DLLs must be copies - Wine resolves symlinks and the game
          # uses the resolved path as its base directory for saves/configs
          copyGlobs = [ ];

          runtime = "proton";

          # Saves persist via the per-game fuse-overlayfs upper (engine writes
          # next to its binary, not under drive_c/users/steamuser/...).
          saveLocations = [ ];
          executable = "SPEED2.EXE";
          gamescope = {
            output-width = 1920;
            output-height = 1080;
            nested-width = 1920;
            nested-height = 1080;
            flags = {
              "-r" = "60";
              "--immediate-flips" = true;
              "--expose-wayland" = true;
            };
          };

          env = {
            STEAM_COMPAT_CONFIG = "sdlinput";
            PULSE_LATENCY_MSEC = "60";
            STAGING_WRITECOPY = "1";
            WINE_LARGE_ADDRESS_AWARE = "1";
          };

          preRun = lib.mkIf (config.enablePlayerSoundtracks || config.extraSoundtracks != [ ]) ''
            # ECM scans `<asi-dir>/<playlist>/` -- with the bundled INI's
            # `playlist = "Music"` and the ASI at SCRIPTS/, that's
            # $STROM_OVERLAY/SCRIPTS/Music. The overlay is writable per
            # launch; populate it with fresh symlinks each time.
            NFSU2_MUSIC="$STROM_OVERLAY/SCRIPTS/Music"
            mkdir -p "$NFSU2_MUSIC"
            # Sweep stale symlinks from previous launches (real files left alone).
            find "$NFSU2_MUSIC" -maxdepth 1 -type l -delete

            # ECM's std::filesystem path handling throws on non-ASCII
            # filenames (kanji, unicode punctuation, ...). Sanitize each
            # symlink's basename to printable 7-bit ASCII; on collision or
            # when the entire name strips empty, prepend a sha256 prefix
            # so every track keeps a unique target.
            strom_link_track() {
              local src="$1" base clean
              base=$(basename "$src")
              clean=$(printf '%s' "$base" | LC_ALL=C tr -cd 'A-Za-z0-9 ._()[]-')
              if [ -z "$clean" ] || [ "$clean" = ".mp3" ]; then
                clean=$(printf '%s' "$src" | sha256sum | cut -c1-8).mp3
              fi
              if [ -e "$NFSU2_MUSIC/$clean" ] || [ -L "$NFSU2_MUSIC/$clean" ]; then
                clean=$(printf '%s' "$src" | sha256sum | cut -c1-8)-$clean
              fi
              ln -sf "$src" "$NFSU2_MUSIC/$clean"
            }

            ${lib.concatMapStringsSep "\n" (m: ''
              while IFS= read -r -d "" f; do
                strom_link_track "$f"
              done < <(find ${m} -type f -print0)
            '') config.extraSoundtracks}

            ${lib.optionalString config.enablePlayerSoundtracks ''
              mkdir -p "$STROM_GAMEDIR/music"
              while IFS= read -r -d "" f; do
                strom_link_track "$f"
              done < <(find "$STROM_GAMEDIR/music" -maxdepth 1 -type f -print0)
            ''}
          '';
        };
      }
    )
  ];

  meta = {
    description = "Need for Speed: Underground 2 (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "need-for-speed-underground-2";
  };
}
