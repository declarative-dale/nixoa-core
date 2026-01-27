{
  inputs,
  config,
  lib,
  ...
}:
let
  featureNames = config.flake.lib.featureNames;
  stackNames = config.flake.lib.stackNames;
  mkFeature = config.flake.lib.mkFeatureModule;
  mkStack = config.flake.lib.mkStackModule;
in
{
  flake = {
    nixosModules =
      (lib.genAttrs featureNames mkFeature)
      // (lib.genAttrs stackNames mkStack)
      // {
        default = mkStack "appliance";
      };

    overlays = {
      nixoa = final: prev: {
        nixoa = {
          xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${final.system}.xen-orchestra-ce;
          libvhdi = inputs.xen-orchestra-ce.packages.${final.system}.libvhdi;
        };
      };

      default = inputs.self.overlays.nixoa;
    };
  };
}
