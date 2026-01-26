{
  inputs,
  ...
}:
{
  flake = {
    nixosModules = {
      nixoaCore = inputs.self.modules.nixos.nixoaCore;
      appliance = inputs.self.modules.nixos.appliance;
      default = inputs.self.modules.nixos.appliance;
    };

    overlays = {
      nixoa = final: prev: {
        nixoa = {
          xen-orchestra-ce = final.callPackage ../../pkgs/xen-orchestra-ce {
            inherit (inputs) xoSrc;
          };
          libvhdi = final.callPackage ../../pkgs/libvhdi {
            inherit (inputs) libvhdiSrc;
          };
        };
      };

      default = inputs.self.overlays.nixoa;
    };
  };
}
