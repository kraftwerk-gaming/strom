let
  flake = builtins.getFlake (toString ./..);
  pkgs = flake.packages.x86_64-linux;
  modules = flake.modules.x86_64-linux;
  names = builtins.attrNames pkgs;

  extract =
    name:
    let
      p = pkgs.${name};
      sources = p.passthru.ipfsSources or [ ];
      cids = builtins.filter (c: c != "") (map (s: s.cid or "") sources);

      # The Android descriptor, so a client can read the catalog over
      # plain HTTP without evaluating Nix. `slug` and `runtime` are
      # dropped: the slug is the directory and `runtime` is already a
      # sibling key, so carrying them again would be the one thing this
      # file exists to avoid.
      m = modules.${name}.android.outputs.manifestAttrs;
      android = builtins.removeAttrs m [
        "slug"
        "runtime"
      ];
    in
    {
      description = p.meta.description or null;
      runtime = p.passthru.runtime or "unknown";
      inherit cids android;
    };
in
builtins.listToAttrs (
  map (n: {
    name = n;
    value = extract n;
  }) names
)
