{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
in {
  flake.packages = lib.genAttrs systems (
    system: let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package:
          lib.getName package == "packer";
      };
      xenOrchestraCe = inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce;
      planRunner = inputs.xen-orchestra-ce.packages.${system}.flake-plan-runner;
      nxcli = pkgs.callPackage ../../pkgs/nxcli/package.nix {};
      nixoaMenu = pkgs.callPackage ../../pkgs/nixoa-menu/package.nix {};
      nixoaCi = pkgs.callPackage ../../nix/automation {inherit planRunner;};
      nixoaCiInstallerBoot = pkgs.callPackage ../../nix/automation/installer-boot-package.nix {};
      nixoaCiUpdateLocks = nixoaCi.commands.update-locks;
      secretspec = pkgs.callPackage ../../nix/pkgs/secretspec.nix {};
      packerXenserverPlugin = pkgs.callPackage ../../pkgs/packer-xenserver-plugin/package.nix {};
      packerXenserver = pkgs.callPackage ../../pkgs/packer-xenserver/package.nix {
        inherit packerXenserverPlugin;
      };
      deployTemplate = pkgs.writeShellApplication {
        name = "nixoa-deploy-template";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.gh
          pkgs.jq
          pkgs.nix
          packerXenserver
        ];
        text = ''
          repo_root="''${NIXOA_SYSTEM_ROOT:-}"
          if [ -z "$repo_root" ]; then
            if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
              repo_root="$git_root"
            else
              repo_root="$PWD"
            fi
          fi

          deploy_script="$repo_root/packer/deploy-template.sh"
          if [ ! -x "$deploy_script" ]; then
            echo "Could not find $deploy_script" >&2
            echo "Run this app from a NiXOA checkout or set NIXOA_SYSTEM_ROOT." >&2
            exit 1
          fi

          export PACKER_BIN=${packerXenserver}/bin/packer-xenserver
          export NIX_BIN=${pkgs.nix}/bin/nix
          exec "$deploy_script" "$@"
        '';
        meta.description = "Deploy a native NiXOA XCP-ng template";
      };
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
        flake-plan-runner = planRunner;
        sbomnix = pkgs.sbomnix;
        inherit secretspec;
        libvhdi = inputs.xen-orchestra-ce.packages.x86_64-linux.libvhdi;
        default = xenOrchestraCe;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        deploy-template = deployTemplate;
        nixoa-ci = nixoaCi;
        nixoa-ci-installer-boot = nixoaCiInstallerBoot;
        nixoa-ci-update-locks = nixoaCiUpdateLocks;
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
