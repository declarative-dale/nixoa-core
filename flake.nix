# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOA-VM - Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Xen Orchestra source (pinned to specific commit for stability)
    xoSrc = {
      url = "github:vatesfr/xen-orchestra";
      flake = false;
    };

    # libvhdi source (pinned release for VHD support)
    libvhdiSrc = {
      url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
      flake = false;
    };

    # User configuration flake (optional, local path on the host)
    nixoa-config = {
      url = "path:/etc/nixos/nixoa/user-config";
      flake = true;
    };
  };

  outputs = { self, nixpkgs, xoSrc, libvhdiSrc, nixoa-config ? null, ... }:
  let
    # System architecture (cannot be overridden by modules)
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    lib = nixpkgs.lib;
  in {
    # Configuration name is always "nixoa" now (not from config)
    nixosConfigurations.nixoa = lib.nixosSystem {
      inherit system;

      modules = [
        # Hardware configuration - imported from user-config
        (if nixoa-config != null && (nixoa-config ? nixosModules) && (nixoa-config.nixosModules ? hardware)
         then nixoa-config.nixosModules.hardware
         else builtins.throw ''
           nixoa-vm: hardware-configuration.nix is missing in user-config!

           Please copy your hardware configuration to user-config:
             sudo cp /etc/nixos/hardware-configuration.nix /etc/nixos/nixoa/user-config/

           Or generate fresh:
             sudo nixos-generate-config --show-hardware-config > /etc/nixos/nixoa/user-config/hardware-configuration.nix

           Then commit the change:
             cd /etc/nixos/nixoa/user-config
             ./commit-config "Add hardware-configuration.nix"
         '')

        # Auto-import all modules from ./modules directory
        # This includes nixoa-options.nix which defines options.nixoa.*
        ./modules

        # Import user configuration module from user-config
        (if nixoa-config != null
         then nixoa-config.nixosModules.default
         else {
           # Minimal defaults if no nixoa-config provided (for development/testing)
           config.nixoa = {
             hostname = "nixoa";
             admin = {
               username = "xoa";
               sshKeys = [];
             };
           };
         })
      ];

      # Provide flake-pinned sources and config to modules
      specialArgs = {
        inherit xoSrc libvhdiSrc nixoa-config;
      };
    };

    # Package metadata for the project
    packages.${system}.default = pkgs.stdenv.mkDerivation {
      pname = "nixoa-vm";
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

    # Runnable helper: nix run .#update-xo
    apps.${system}.update-xo = {
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
          echo "📦 To rebuild: sudo nixos-rebuild switch --flake .#nixoa"
        '';
      });
      meta = with pkgs.lib; {
        description = "Update the xoSrc input in flake.lock and show new commits.";
        license = licenses.asl20;
        platforms = platforms.linux;
      };
    };

    # Development shell
    devShells.${system}.default = pkgs.mkShell {
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
        echo "║           XOA Development Environment                      ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "📋 Available commands:"
        echo "  nix run .#update-xo                    - Update XO source"
        echo "  sudo nixos-rebuild switch --flake .#nixoa - Deploy changes"
        echo "  sudo nixos-rebuild test --flake .#nixoa   - Test changes"
        echo "  nix flake check                        - Validate flake"
        echo "  nix flake show                         - Show flake outputs"
        echo ""
        echo "📁 Module locations:"
        echo "  ./modules/system.nix  - Core system configuration"
        echo "  ./modules/xoa.nix     - Xen Orchestra service"
        echo "  ./modules/storage.nix - NFS/CIFS mount support"
        echo "  ./modules/libvhdi.nix - VHD image support"
        echo "  ./modules/extras.nix  - Terminal enhancements"
        echo "  ./vars.nix            - User configuration"
        echo ""
      '';
    };
  };
}
