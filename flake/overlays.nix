# Overlay exports
{ self, inputs, ... }:
{
  flake = {
    overlays.default = final: prev: {
      nixoa = {
        xen-orchestra-ce = final.callPackage ../pkgs/xen-orchestra-ce {
          inherit (inputs) xoSrc;
        };
        libvhdi = final.callPackage ../pkgs/libvhdi {
          inherit (inputs) libvhdiSrc;
        };
      };
    };
  };
}
