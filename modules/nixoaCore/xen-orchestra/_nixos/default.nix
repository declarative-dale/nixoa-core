{ inputs, ... }:
let
  overlay = final: _prev:
    let
      system = final.stdenv.hostPlatform.system;
    in
    {
      nixoa =
        {
          xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
          libvhdi = inputs.xen-orchestra-ce.packages.${system}.libvhdi;
        }
        // inputs.nixpkgs.lib.optionalAttrs final.stdenv.hostPlatform.isLinux {
          nixoa-menu = final.callPackage ../../../../pkgs/nixoa-menu/package.nix { };
        };
    };
in
{
  nixpkgs.overlays = [ overlay ];

  imports = [
    ../../../_nixos/features/shared/context.nix
    (inputs.import-tree ../../../_nixos/features/xen-orchestra)
  ];
}
