# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOA-VM - Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Flakeparts for modular flake structure
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Home Manager for user environment management
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Xen Orchestra source - pinned to v6.0.2 (commit b89c26459cfd301bb92adf0a98a0b2dbab57e487)
    # Uses fetchYarnDeps for offline, hash-pinned dependencies
    # Explicit yarn install --offline --frozen-lockfile ensures deterministic builds
    xoSrc = {
      url = "github:vatesfr/xen-orchestra/b89c26459cfd301bb92adf0a98a0b2dbab57e487";
      flake = false;
    };

    # libvhdi source (pinned release for VHD support)
    libvhdiSrc = {
      url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
      flake = false;
    };

  };

  outputs = inputs @ { self, flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      flake = {
        # Module library export - core is a module provider for system flake
        # Usage in system flake: core.nixosModules.default
        nixosModules.default = { config, lib, pkgs, ... }:
          let
            utils = import ./lib/utils.nix { inherit lib; };
          in
          {
            imports = [
              # Auto-import all modules EXCEPT home/ (handled separately in system flake)
              ./modules
            ];

            # Make packages and utilities available to all modules
            _module.args = {
              nixoaPackages = self.packages.${pkgs.system};
              nixoaUtils = utils;
              xoTomlData = null;  # Only provided by system flake when available
            };
          };

        # Overlay for easy nixpkgs extension
        # Usage: overlays.default (adds nixoa.xen-orchestra-ce and nixoa.libvhdi to pkgs)
        overlays.default = final: prev: {
          nixoa = {
            xen-orchestra-ce = self.packages.${final.system}.xen-orchestra-ce;
            libvhdi = self.packages.${final.system}.libvhdi;
          };
        };

        # Test configuration - validates that modules can be instantiated
        nixosConfigurations.nixoa = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            self.nixosModules.default

            # Minimal test configuration
            {
              # Minimal hardware configuration for test build
              # Boot configuration now handled by boot.nix with systemd-boot as default
              # To use GRUB instead, override:
              # nixoa.boot.loader = "grub";
              # nixoa.boot.grub.device = "/dev/sda";

              fileSystems."/" = {
                device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
                fsType = "ext4";
              };

              system.stateVersion = "25.11";
            }
          ];
        };
      };

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        # Package outputs - XOA and libvhdi built from source
        packages = {
          xen-orchestra-ce = pkgs.callPackage ./pkgs/xen-orchestra-ce { inherit (inputs) xoSrc; };
          libvhdi = pkgs.callPackage ./pkgs/libvhdi { inherit (inputs) libvhdiSrc; };
          default = config.packages.xen-orchestra-ce;

          # Package metadata for the project
          metadata = pkgs.stdenv.mkDerivation {
            pname = "nixoa-vm-metadata";
            version = "1.0.0";
            dontUnpack = true;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/share/doc/nixoa-vm
              echo "NixOA-VM - Xen Orchestra Community Edition on NixOS" > $out/share/doc/nixoa-vm/README
              echo "This is a NixOS configuration flake." >> $out/share/doc/nixoa-vm/README
              echo "See https://codeberg.org/nixoa/nixoa-vm for details." >> $out/share/doc/nixoa-vm/README
            '';
            meta = with pkgs.lib; {
              description = "Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";
              longDescription = ''
                An experimental Xen Orchestra Community Edition deployment for NixOS,
                ideal for homelab and testing environments.

                WARNING: This is NOT production-ready and NOT supported by Vates.
                For production use, purchase the official Xen Orchestra Appliance (XOA)
                from Vates which includes professional support and SLA options.

                Author and Maintainer: Dale Morgan
                Licensed as of: December 3, 2025
              '';
              license = licenses.asl20;
              maintainers = [{
                name = "Dale Morgan";
                codeberg = "dalemorgan";
              }];
              platforms = platforms.linux;
              homepage = "https://codeberg.org/nixoa/nixoa-vm";
            };
          };
        };

        # Runnable helper: nix run .#update-xo
        apps.update-xo = {
          type = "app";
          program = toString (pkgs.writeShellApplication {
            name = "update-xo";
            runtimeInputs = [ pkgs.jq pkgs.git pkgs.curl ];
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail

              echo "🔄 Updating Xen Orchestra source..."
              nix flake lock --update-input xoSrc

              echo "📋 Recent commits in xen-orchestra:"
              curl -s https://api.github.com/repos/vatesfr/xen-orchestra/commits?per_page=5 | \
                jq -r '.[] | "  • \(.sha[0:7]) - \(.commit.message | split("\n")[0]) (\(.commit.author.date))"'

              echo ""
              echo "✅ Update complete! Review changes with: git diff flake.lock"
              echo ""
              echo "📦 To rebuild with core updates:"
              echo "   cd ~/projects/NiXOA/system && sudo nixos-rebuild switch --flake ."
            '';
          });
          meta = with pkgs.lib; {
            description = "Update the xoSrc input in flake.lock and show new commits.";
            license = pkgs.lib.licenses.asl20;
            platforms = pkgs.lib.platforms.linux;
          };
        };

        # Validation checks - run with `nix flake check`
        # The nixosConfigurations.nixoa serves as the primary check,
        # validating that all modules can be evaluated and instantiated correctly
        checks = {
          # Verify the nixosConfiguration can be built (validates all modules)
          configuration = self.nixosConfigurations.nixoa.config.system.build.toplevel;
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            jq
            git
            curl
            nixos-rebuild
            nix-tree
            nix-diff
          ];

          shellHook = ''
            echo "╔══════════════════════════════════════════════════════════╗"
            echo "║        NixOA Core Module Library - Dev Environment        ║"
            echo "╚══════════════════════════════════════════════════════════╝"
            echo ""
            echo "📋 This is the core module library (immutable, git-managed)"
            echo ""
            echo "📁 Module organization:"
            echo "  ./modules/core/     - System modules (users, network, packages, services)"
            echo "  ./modules/xo/       - XO-specific modules (xoa, storage, autocert, etc.)"
            echo "  ./modules/default.nix - Module entry point (explicit imports)"
            echo ""
            echo "📝 Available commands:"
            echo "  nix run .#update-xo                - Update XO source code"
            echo "  nix flake check                    - Validate flake"
            echo "  nix flake show                     - Show flake outputs"
            echo ""
            echo "⚙️  Module usage:"
            echo "  system imports this as: core.nixosModules.default"
            echo "  System rebuilds from system flake: cd ~/projects/NiXOA/system && sudo nixos-rebuild switch --flake ."
            echo ""
            echo "📝 Configuration files are in the system flake directory"
            echo "  Edit system/configuration.nix to customize settings"
            echo ""
          '';
        };
      };
    };
}
