{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "burnout-3-takedown";
  src = fetchIpfs {
    cid = "QmTR7JR8zd4yENd9sudBy5iQBKRKKvYuB66vhymrRMLmSn";
    fallbackUrl = "https://archive.org/download/burnout-3-takedown-usa_202211/Burnout%203%20-%20Takedown%20%28USA%29.iso";
    hash = "sha256-re+KTNsyEM6c+ljytNKBdyWQYhdBsCNabQbm1fwvOQo=";
    name = "burnout-3-takedown-usa.iso";
  };
  runtime = "pcsx2";
  executable = "burnout-3-takedown-usa.iso";

  meta = {
    description = "Burnout 3: Takedown (via PCSX2)";
    mainProgram = "burnout-3-takedown";
    platforms = [ "x86_64-linux" ];
  };
}
