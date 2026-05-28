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

        # Tree containing ONLY `SCRIPTS/Music/<sanitized-basename>` symlinks
        # into the user's extraSoundtracks derivations. Shipped as a
        # separate overlay lower above _gameData so changing the soundtrack
        # list never re-extracts the 7z game tree. The kernel-overlay merge
        # at /SCRIPTS/ exposes both gameData's SCRIPTS contents (ECM ASI,
        # INI, BASS, deadlock fix, ...) and this layer's SCRIPTS/Music/*
        # transparently. Runtime user-drops in
        # ~/.strom/need-for-speed-underground-2/SCRIPTS/Music/ land in the
        # overlay upper and still show up in the merged view.
        soundtracks = runCommandLocal "need-for-speed-underground-2-soundtracks" { } ''
          mkdir -p "$out/SCRIPTS/Music"

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
            if [ -e "$out/SCRIPTS/Music/$clean" ] || [ -L "$out/SCRIPTS/Music/$clean" ]; then
              clean=$(printf '%s' "$src" | sha256sum | cut -c1-8)-$clean
            fi
            ln -s "$src" "$out/SCRIPTS/Music/$clean"
          }

          ${lib.concatMapStringsSep "\n" (m: ''
            while IFS= read -r -d "" f; do
              strom_link_track "$f"
            done < <(find ${m} -type f -print0)
          '') config.extraSoundtracks}
        '';
      in
      {
        options = {
          enablePlayerSoundtracks = mkOption {
            type = types.bool;
            default = false;
            description = ''
              When true, install ECM (External Custom Music, an ASI
              plugin) into `SCRIPTS/` and let the player drop tracks
              into `~/.strom/need-for-speed-underground-2/SCRIPTS/Music/`
              at runtime. The drop directory is the overlay UPPER, so
              files there merge with the build-time `extraSoundtracks`
              (shipped as a separate overlay lower) and become visible
              to ECM without a rebuild. Supported formats per ECM:
              wav, mp1, mp2, mp3, ogg, aif. F11 in-game toggles the
              ECM overlay (volume / skip / playlist).
            '';
          };

          extraSoundtracks = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = ''
              Audio derivations to install at build time. Every regular
              file found under each derivation (recursive) is symlinked
              into a SEPARATE overlay-lower derivation at
              `SCRIPTS/Music/<basename>`. That layer is stacked above
              `_gameData` via `bwrap.overlay.lowers`, so adding/removing
              tracks here does NOT trigger re-extraction of the 7z game
              tree, and the files do NOT live in gameData or in the
              user's `~/.strom/...` state. Runtime user-drops in
              `~/.strom/need-for-speed-underground-2/SCRIPTS/Music/`
              (the overlay upper) still show up alongside these tracks
              in the merged view. Supported formats per ECM: wav, mp1,
              mp2, mp3, ogg, aif. Typical sources are `pkgs.fetchurl`
              for individual tracks or a `runCommand` that transcodes
              a directory of source files.

              Note: symlink basenames are sanitized to 7-bit ASCII
              (`A-Za-z0-9 ._()[]-`) before being placed in `Music/`.
              ECM's `std::filesystem` enumeration crashes on filenames
              containing kanji or unicode punctuation, so non-ASCII
              bytes are stripped and collisions resolved by prepending
              a sha256 prefix. The source derivation is untouched;
              only the in-overlay symlink name changes.
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
              # ASI; default `playlist = "Music"` -> `SCRIPTS/Music/`.
              # The actual tracks live in a separate overlay lower (see
              # `soundtracks` below) so soundtrack changes don't re-7z
              # the game tree; runtime drops land in the overlay upper
              # at ~/.strom/<game>/SCRIPTS/Music/.
              cp ${ecm}/ecm.x86.asi "$out/SCRIPTS/"
              cp ${ecm}/ecm.x86.ini "$out/SCRIPTS/"
              cp ${ecm}/bass.dll    "$out/SCRIPTS/"
            ''}
          '';

          # Stack soundtracks above _gameData (kernel-priority order:
          # mkBefore prepends, so soundtracks wins on any path conflict
          # at SCRIPTS/Music/*; _gameData stays the base lower).
          bwrap.overlay.lowers = lib.mkBefore (
            lib.optional (config.enablePlayerSoundtracks || config.extraSoundtracks != [ ]) "${soundtracks}"
          );

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
