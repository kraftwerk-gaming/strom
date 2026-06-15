{
  self,
  lib,
  pkgs,
  fetchIpfs,
  libarchive,
}:

let
  # The Backrooms: 1998 (Steelkrill Studio, 2022) -- the genuinely free
  # "Found Footage Backroom Horror" teaser/demo build (steelkrill.itch.io/1998,
  # min_price 0), distinct from the paid full release. Unity Mono 32-bit
  # Windows build, so runtime = "proton". The itch download is a RAR5
  # archive ("The Backrooms 98 Free.rar", 475 MB) with the game tree under
  # a single wrapper folder "The Backrooms 98 Free/" (the .exe +
  # _Data/ + UnityPlayer.dll + MonoBleedingEdge/). itch's R2 CDN URLs are
  # short-lived signed links, so fallbackUrl points at the canonical itch
  # page; the source is pinned to IPFS (cid above) once verified.
  src = fetchIpfs {
    cid = "QmUU5ZeXzio1BcLRaNcqmNP96Jy7riyWydiogQc1RAQxfX";
    fallbackUrl = "https://steelkrill.itch.io/1998";
    hash = "sha256-uPsCwUhbikJL0ppIJE4qKEc3ZuBHcm0v7Vdze+3Xdck=";
    name = "the-backrooms-98-free.rar";
  };

  # GE-Proton bundles ffmpeg 4.x (libavcodec.so.58) for winegstreamer, but
  # that libavcodec is NEEDED-linked against libvpx.so.6 (libvpx 1.9.x) --
  # a soname nixpkgs no longer ships (current libvpx is .so.12). Pin 1.9.0
  # so Proton's bundled libavcodec/libgstlibav can resolve it in the FHS.
  # This is a 32-bit Unity build, so the i686 libvpx is the one that lands
  # in the multilib /usr/lib32 FHS (the i386 libgstlibav lives there).
  libvpx6_32 = pkgs.pkgsi686Linux.libvpx.overrideAttrs (old: {
    version = "1.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "webmproject";
      repo = "libvpx";
      rev = "v1.9.0";
      hash = "sha256-PsN8AOHZalYaB9OCu1yS5vJTvN8BAx8gCU8gtqoyu5s=";
    };
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-backrooms-1998";

  ipfsSources = [ src ];
  inherit src;

  # bsdtar (libarchive) reads the RAR5 container; nixpkgs' unrar is unfree
  # and p7zip 17.05 can't open RAR5, so libarchive is the only free
  # in-sandbox extractor here.
  nativeBuildInputs = [ libarchive ];

  buildScript = ''
    mkdir -p "$out"
    bsdtar -xf "$src" -C "$TMPDIR"
    cp -a "$TMPDIR/The Backrooms 98 Free/." "$out"/
    # UnityCrashHandler32.exe lingers after a clean quit and wedges proton's
    # waitforexitandrun, so gamescope never tears down. Unity runs fine
    # without it, so drop it for a clean exit.
    rm -f "$out/UnityCrashHandler32.exe"
  '';

  runtime = "proton";
  executable = "The Backrooms 98 Free.exe";

  # Unity persistentDataPath AppData/LocalLow/<company>/<product>; company
  # "SteelkrillStudio" and product "The Backrooms 98 FREE DEMO" are taken
  # verbatim from _Data/app.info lines 1 and 2.
  # Fix the in-game black screen. This "found footage" horror demo plays
  # H.264/AAC VHS clips (avc1/mp4a, embedded in sharedassets*.resource)
  # through Unity's WindowsVideoMedia backend -> Wine Media Foundation ->
  # Proton winegstreamer -> the bundled gstreamer H.264 decoder
  # libgstlibav.so -> libavcodec.so.58. That libav stack is NEEDED-linked
  # against a chain of host libs GE-Proton expects from the Steam Linux
  # Runtime container -- libbz2.so.1.0 (libavformat), libvpx.so.6 +
  # libva.so.2 (libavcodec), libva-drm/-x11.so.2 + libvdpau.so.1
  # (libavutil) -- none of which strom's FHS carries. The dlopen fails,
  # gstreamer registers no H.264 decoder, Media Foundation can't build a
  # pipeline and CreateObjectFromByteStream fails with WindowsVideoMedia
  # error 0xc00d36bb (MF_E_UNSUPPORTED_BYTESTREAM_TYPE); the game's video
  # coroutine then waits forever on a VideoPlayer end event that never
  # fires, so gameplay never presents (black screen on PLAY TAPE).
  #
  # This is a PE32 (32-bit) Unity Mono build, so the decoder that loads is
  # the i386 libgstlibav under files/lib/i386-linux-gnu; the libs must
  # therefore land in the 32-bit /usr/lib32 FHS, hence pkgsi686Linux.*
  # (strom-fhs partitions targetPkgs by host system into fhs32/fhs64).
  targetPkgs = p: [
    p.pkgsi686Linux.bzip2
    p.pkgsi686Linux.libva
    p.pkgsi686Linux.libvdpau
    libvpx6_32
  ];

  saveLocations = [ "AppData/LocalLow/SteelkrillStudio/The Backrooms 98 FREE DEMO" ];

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
    description = "The Backrooms: 1998 (Steelkrill Studio 2022, free found-footage horror demo, Unity Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-backrooms-1998";
  };
}
