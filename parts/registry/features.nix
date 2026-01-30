{
  lib,
  ...
}:
let
  feature = modules: { inherit modules; };

  commonModules = [
    ../../modules/features/foundation/args.nix
  ];
  platform = import ./features/platform.nix { };
  virtualization = import ./features/virtualization.nix { };
  xo = import ./features/xo.nix { };

  mkFeatureEntries =
    group: modulesByName:
    lib.mapAttrs'
      (name: modules: lib.nameValuePair "${group}-${name}" (feature modules))
      modulesByName;

  features =
    lib.foldl' lib.mergeAttrs { }
      (lib.mapAttrsToList mkFeatureEntries {
        platform = platform.modules;
        virtualization = virtualization.modules;
        xo = xo.modules;
      });

  platformStack = map (name: "platform-${name}") platform.order;
  virtualizationStack = map (name: "virtualization-${name}") virtualization.order;
  xoStack = map (name: "xo-${name}") xo.order;
in
{
  options.flake.registry = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  config.flake.registry = {
    modules = {
      common = commonModules;
    };

    inherit features;

    stacks = {
      platform = platformStack;
      xo = xoStack;
      appliance = platformStack ++ virtualizationStack ++ xoStack;
    };
  };
}
