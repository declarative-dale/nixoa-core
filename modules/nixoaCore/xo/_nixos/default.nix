{
  inputs,
  context,
  ...
}: let
  overlay = final: _prev: let
    system = final.stdenv.hostPlatform.system;
    xenOrchestraCe = import ../../../../lib/xen-orchestra-ce-package.nix {
      xenOrchestraCe = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
    };
  in {
    nixoa =
      {
        xen-orchestra-ce = xenOrchestraCe;
        libvhdi = inputs.xen-orchestra-ce.packages.${system}.libvhdi;
      }
      // inputs.nixpkgs.lib.optionalAttrs final.stdenv.hostPlatform.isLinux {
        nxcli = final.callPackage ../../../../pkgs/nxcli/package.nix {
          repoRootDefault = context.repoDir;
        };
        nixoa-menu = final.callPackage ../../../../pkgs/nixoa-menu/package.nix {};
      };
  };
in {
  nixpkgs.overlays = [overlay];

  imports = [
    ../../../_nixos/features/shared/context.nix
    (inputs.import-tree ../../../_nixos/features/xen-orchestra)
  ];
}
