{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  mkPcsx2Game = self.lib.mkPcsx2Game { inherit lib pkgs; };
in
mkPcsx2Game {
  name = "burnout-3-takedown";
  src = fetchIpfs {
    cid = "placeholder";
    fallbackUrl = "https://archive.org/download/burnout-3-takedown-usa_202211/Burnout%203%20-%20Takedown%20%28USA%29.iso";
    hash = "sha256-re+KTNsyEM6c+ljytNKBdyWQYhdBsCNabQbm1fwvOQo=";
    name = "burnout-3-takedown-usa.iso";
  };
  description = "Burnout 3: Takedown (via PCSX2)";
}
