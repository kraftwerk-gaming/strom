let
  flake = builtins.getFlake (toString ./..);
  pkgs = flake.packages.x86_64-linux;
  names = builtins.attrNames pkgs;

  extract =
    name:
    let
      p = pkgs.${name};
      sources = p.passthru.ipfsSources or [ ];
      cids = builtins.filter (c: c != "") (map (s: s.cid or "") sources);
    in
    {
      description = p.meta.description or null;
      runtime = p.passthru.runtime or "unknown";
      inherit cids;
    };
in
builtins.listToAttrs (
  map (n: {
    name = n;
    value = extract n;
  }) names
)
