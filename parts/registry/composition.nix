{
  lib,
  config,
  ...
}:
let
  registry = config.flake.registry or { };
  commonModules = registry.modules.common or [ ];
  featureNames = builtins.attrNames (registry.features or { });
  stackNames = builtins.attrNames (registry.stacks or { });
  resolveFeature = name: registry.features.${name};

  featureModules =
    names:
    let
      getModules = feature: if feature ? modules then feature.modules else [ feature.module ];
    in
    commonModules ++ lib.concatMap (name: getModules (resolveFeature name)) names;
  stackModules = name: featureModules registry.stacks.${name};

  mkFeatureModule = name: { imports = featureModules [ name ]; };
  mkStackModule = name: { imports = stackModules name; };
in
{
  # Shared helpers for feature-centric composition.
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  config.flake.lib = {
    inherit
      featureNames
      stackNames
      resolveFeature
      featureModules
      stackModules
      mkFeatureModule
      mkStackModule
      ;
  };
}
