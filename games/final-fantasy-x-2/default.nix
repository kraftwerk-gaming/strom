{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

# Final Fantasy X-2 (Square Enix 2003), the original PlayStation 2 release,
# run via PCSX2. This is the disc game, not the 2013/2016 "FFX/X-2 HD
# Remaster" -- a different product with different assets, so its Steam
# listing is deliberately not attached (metadata.json pins "appid": null).
#
# Dump: Redump "Final Fantasy X-2 (USA, Canada)", NTSC-U retail, serial
# SLUS-20672, from the archive.org `ps2-redump-usa-chd-part-F` Redump set.
# PCSX2 confirms the disc on boot: Serial SLUS-20672, CRC 48FE0C71, video
# mode NTSC -- i.e. this is X-2 and not FFX (SLUS-20312), which several
# uploads bundle or mislabel.
#
# Shipped as MAME CHD rather than a raw ISO: 3.44 GiB instead of the
# 3.98 GiB DVD image, and PCSX2 reads CHD natively via libchdr, so there
# is no decompression build step. Not recompressed by us; `chdman info`
# reports logical size 4,760,008,704 (1,944,448 units), SHA1
# c394e9cad3511d043592f13a7d3f943f94cc1e71.
self.lib.mkGame { inherit lib pkgs; } {
  name = "final-fantasy-x-2";
  src = fetchIpfs {
    cid = "Qmba1no1hhMsWPWkdu8SFbaspCYwqZSaLaFd2vzbd2CkW5";
    fallbackUrl = "https://archive.org/download/ps2-redump-usa-chd-part-F/Final%20Fantasy%20X-2%20%28USA%2C%20Canada%29.chd";
    hash = "sha256-vzjNlPZ83dEnVrWPVo7+oImg/GYLEOoPoiKyXrDXBGo=";
    name = "final-fantasy-x-2-usa.chd";
  };
  runtime = "pcsx2";
  executable = "final-fantasy-x-2-usa.chd";

  meta = {
    description = "Final Fantasy X-2 (PS2 NTSC-U, via PCSX2)";
    mainProgram = "final-fantasy-x-2";
    platforms = [ "x86_64-linux" ];
  };
}
