# Overlay exports
{ self, ... }:
{
  flake = {
    overlays.default = final: prev: {
      nixoa = {
        xen-orchestra-ce = self.packages.${final.system}.xen-orchestra-ce;
        libvhdi = self.packages.${final.system}.libvhdi;
      };
    };
  };
}
