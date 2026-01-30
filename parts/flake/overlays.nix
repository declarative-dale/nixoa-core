# SPDX-License-Identifier: Apache-2.0
# Flake overlay outputs
{
  inputs,
  ...
}:
{
  flake.overlays = {
    nixoa = final: prev: {
      nixoa = {
        xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${final.system}.xen-orchestra-ce;
        libvhdi = inputs.xen-orchestra-ce.packages.${final.system}.libvhdi;
      };
    };

    default = inputs.self.overlays.nixoa;
  };
}
