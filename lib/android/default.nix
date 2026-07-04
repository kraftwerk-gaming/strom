# lib/android/default.nix
#
# Android sub-module of mkGame. Sits alongside `proton`, `bwrap`,
# `gamescope`, etc.; consumers reach the artifact via
# `<game>.android.outputs.apk` (or the flake-level `apks.<slug>` alias).
#
# This is a plain submodule (not a wrapper module from wrappers.lib):
# an APK isn't a shell wrapper around an exe and the wrapper schema's
# `package`/`exePath`/etc. have no meaning here. The parent mk-game
# config is passed in via the `game` specialArg so a builder can read
# game.name / game.env / etc. directly without duplicating options.
#
# There is deliberately NO default APK pipeline here: outputs.apk is a
# per-game seam. A game that can be packaged for Android (e.g. a LÖVE
# game via a self-contained tool like balatromobile — see
# games/balatro/apk.nix) plugs its own derivation into
# `android.outputs.apk`. A generic Wine/FEX ("proton-android") pipeline
# existed as a default builder on the feature/balatro-mobile branch but
# never reached a working state for a real game, so it was dropped;
# resurrect it from that branch history if the need returns.

{
  lib,
  game,
  ...
}:

let
  inherit (lib) mkOption types;

  # Android package names disallow hyphens; the appId stem is the slug
  # with `-` stripped ("balatro" stays "balatro",
  # "need-for-speed-underground-2" -> "needforspeedunderground2").
  slugToAppId = slug: lib.replaceStrings [ "-" ] [ "" ] slug;
in
{
  options = {
    appId = mkOption {
      type = types.str;
      default = "gaming.kraftwerk.strom.${slugToAppId game.name}";
      defaultText = lib.literalMD "`gaming.kraftwerk.strom.<game.name stripped of hyphens>`";
      description = "Android application id for the game's APK.";
    };

    versionName = mkOption {
      type = types.str;
      default = "0.1.0";
      description = "Android versionName stamped into the APK manifest.";
    };

    outputs.apk = mkOption {
      type = types.package;
      description = ''
        The signed APK derivation. No default: each game that supports
        an Android build defines this with its own packaging pipeline
        (see games/balatro/apk.nix for the balatromobile-based LÖVE
        example). Evaluating it for a game that doesn't define it is an
        error.
      '';
    };
  };
}
