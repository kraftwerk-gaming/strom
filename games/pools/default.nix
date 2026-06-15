{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # POOLS (Tensori 2024). Wordless liminal drained-pool walking-horror.
  # Despite being commonly described as "Unreal Engine", the shipped build
  # is a Unity IL2CPP game (UnityPlayer.dll + GameAssembly.dll +
  # POOLS_Data/il2cpp_data + the *_Data layout), DX12 backend (D3D12/
  # D3D12Core.dll Agility SDK runtime ships alongside the exe).
  #
  # Source: STEAMRIP pre-installed release mirrored on archive.org as a
  # single RAR5. The repack is cracked by TENOKE: a drop-in
  # steam_api64.dll emu under POOLS_Data/Plugins/x86_64 driven by the
  # adjacent tenoke.ini (pinned to appid 2663530, language=english). The
  # emu is a static DLL replacement that fakes SteamAPI_Init() with no
  # Steam client, so it works under GE-Proton exactly like the Goldberg /
  # gbe_fork swap other Unity titles use here.
  src = fetchIpfs {
    cid = "QmdEe9RAT2md6TaVzgtMzG5Jw7bvmtfvtWhDeJPvzrfJ5m";
    fallbackUrl = "https://archive.org/download/pools-steam-rip.com/POOLS-SteamRIP.com.rar";
    hash = "sha256-hJENXHyU7N/uCcGUl3tEd7OkRJfC0SHT8TTCkEW12BM=";
    name = "POOLS-SteamRIP.com.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pools";

  inherit src;

  nativeBuildInputs = [ unar ];

  # The rar wraps everything under POOLS-SteamRIP.com/POOLS/. Strip both
  # wrapper levels so $out/POOLS.exe sits at the root next to UnityPlayer.dll,
  # GameAssembly.dll, the POOLS_Data tree and the D3D12/ Agility SDK dir.
  # The _CommonRedist installers and the SteamRIP advert .url are dropped:
  # Proton provides the VC/dotNet/OpenAL runtime, and the TENOKE emu is
  # already in place.
  buildScript = ''
    mkdir -p "$out"
    unar -q -f -o "$TMPDIR/x" "$src"
    d=$(dirname "$(find "$TMPDIR/x" -name POOLS.exe -print -quit)")
    cp -r "$d"/. "$out"/
    chmod -R u+w "$out"
    test -f "$out/POOLS.exe" \
      || { echo "POOLS.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/POOLS_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "steam_api64.dll (TENOKE emu) missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "POOLS.exe";

  env = {
    SteamAppId = "2663530";
    SteamGameId = "2663530";
  };

  # Unity IL2CPP per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\ with the
  # names read from POOLS_Data/app.info ("Tensori" / "POOLS").
  saveLocations = [ "AppData/LocalLow/Tensori/POOLS" ];

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
    description = "POOLS (Tensori 2024, liminal walking-horror, Unity IL2CPP via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pools";
  };
}
