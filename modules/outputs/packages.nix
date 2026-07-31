{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
in {
  flake.packages = lib.genAttrs systems (
    system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      xenOrchestraCe = inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce;
      nxcli = pkgs.callPackage ../../pkgs/nxcli/package.nix {};
      nixoaMenu = pkgs.callPackage ../../pkgs/nixoa-menu/package.nix {};
      applianceToplevel = inputs.self.nixosConfigurations.nixoa.config.system.build.toplevel;
      installerSystem = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [../../installer];
        specialArgs = {
          inherit applianceToplevel nixoaMenu xenOrchestraCe;
        };
      };
      installerIso = assert builtins.elem applianceToplevel installerSystem.config.isoImage.storeContents;
      assert builtins.elem nixoaMenu installerSystem.config.isoImage.storeContents;
      assert builtins.elem xenOrchestraCe installerSystem.config.isoImage.storeContents;
        installerSystem.config.system.build.isoImage;
    in
      {
        xen-orchestra-ce = xenOrchestraCe;
        libvhdi =
          inputs.xen-orchestra-ce.packages.x86_64-linux.libvhdi-fuse2
          or inputs.xen-orchestra-ce.packages.x86_64-linux.libvhdi;
        default = xenOrchestraCe;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nxcli = nxcli;
        nixoa-menu = nixoaMenu;
      }
      // {
        installer-iso = installerIso;
        metadata = pkgs.stdenv.mkDerivation {
          pname = "nixoa-metadata";
          version = "3.1.0";
          dontUnpack = true;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/doc/nixoa
            echo "NiXOA - Xen Orchestra Community Edition on NixOS" > $out/share/doc/nixoa/README
            echo "This flake defines the single nixoa XCP-ng appliance." >> $out/share/doc/nixoa/README
            echo "See https://codeberg.org/NiXOA/core for details." >> $out/share/doc/nixoa/README
          '';
          meta = with pkgs.lib; {
            description = "Xen Orchestra Community Edition appliance for XCP-ng";
            homepage = "https://codeberg.org/NiXOA/core";
            license = licenses.asl20;
            maintainers = [
              {
                name = "Dale Morgan";
                codeberg = "dalemorgan";
              }
            ];
            platforms = platforms.linux;
          };
        };
      }
  );
}
