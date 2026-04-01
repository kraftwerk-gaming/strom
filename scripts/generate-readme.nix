let
  flake = builtins.getFlake (toString ./..);
  pkgs = flake.packages.x86_64-linux;
  names = builtins.attrNames pkgs;

  extract =
    name:
    let
      p = pkgs.${name};
    in
    {
      description = p.meta.description or null;
      homepage = p.meta.homepage or null;
      runtime = p.passthru.runtime or "unknown";
    };
in
builtins.listToAttrs (
  map (n: {
    name = n;
    value = extract n;
  }) names
)
