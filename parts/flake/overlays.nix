# SPDX-License-Identifier: Apache-2.0
# Flake overlay outputs
{
  inputs,
  ...
}:
{
  flake.overlays = {
    nixoa = final: prev:
    let
      system = final.stdenv.hostPlatform.system;
    in
    {
      nixoa = {
        xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
        libvhdi = inputs.xen-orchestra-ce.packages.${system}.libvhdi;
      };
    };

    default = inputs.self.overlays.nixoa;
  };
}
