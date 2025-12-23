# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOA-VM - Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Home Manager for user environment management
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    # User configuration flake
    # Located at /etc/nixos/nixoa/user-config
    # Setup: git clone https://codeberg.org/nixoa/user-config.git /etc/nixos/nixoa/user-config
    nixoa-config = {
      url = "path:/etc/nixos/nixoa/user-config";
      flake = true;
    };
  };

  outputs = { self, nixpkgs, home-manager, xoSrc, libvhdiSrc, nixoa-config ? null, ... }:
  let
    # System architecture (cannot be overridden by modules)
    system = "x86_64-linux";
    lib = nixpkgs.lib;

    # Only import pkgs where needed (for packages/apps/devShells)
    pkgs = nixpkgs.legacyPackages.${system};

    # Extract user args from nixoa-config for use with specialArgs and Home Manager
    # These values will be available as module function arguments in both NixOS and HM modules
    userArgs =
      if nixoa-config != null && nixoa-config ? nixoa && nixoa-config.nixoa ? specialArgs
      then nixoa-config.nixoa.specialArgs
      else {
        # Fallback defaults if no nixoa-config provided (for development/testing)
        username = "xoa";
        hostname = "nixoa";
        system = "x86_64-linux";
        userSettings = { packages.extra = []; extras.enable = false; };
        systemSettings = {
          hostname = "nixoa";
          username = "xoa";
          stateVersion = "25.11";
          sshKeys = [];
          xo = { port = 80; httpsPort = 443; };
          storage.mountsDir = "/var/lib/xo/mounts";
        };
        xoTomlData = null;
      };

    # Extract hostname and XO TOML data for convenience
    configHostname = userArgs.systemSettings.hostname or userArgs.hostname or "nixoa";
    xoTomlData = userArgs.xoTomlData or null;
  in {
    # Configuration name comes from user-config, defaults to "nixoa"
    # Users can customize by setting hostname in configuration.nix
    nixosConfigurations.${configHostname} = lib.nixosSystem {
      inherit system;

      modules = [
        # Hardware configuration - imported directly from user-config directory
        (if nixoa-config != null
         then "${nixoa-config}/hardware-configuration.nix"
         else builtins.throw ''
           nixoa-vm: user-config flake not found!

           Setup steps:
           1. Clone user-config to /etc/nixos/nixoa:
              sudo git clone https://codeberg.org/nixoa/user-config.git /etc/nixos/nixoa/user-config

           2. Ensure hardware configuration exists:
              ls /etc/nixos/nixoa/user-config/hardware-configuration.nix

              If missing, copy or generate:
              sudo cp /etc/nixos/hardware-configuration.nix /etc/nixos/nixoa/user-config/
              OR
              sudo nixos-generate-config --show-hardware-config > /etc/nixos/nixoa/user-config/hardware-configuration.nix

           3. Commit the change:
              cd /etc/nixos/nixoa/user-config
              sudo git add hardware-configuration.nix
              sudo git commit -m "Add hardware-configuration.nix"
         '')

        # Auto-import all modules from ./modules directory
        ./modules

        # Home Manager NixOS module - manages user environment
        home-manager.nixosModules.home-manager

        # Home Manager configuration
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;

            # Pass the same args to Home Manager as NixOS
            extraSpecialArgs = userArgs;

            # Configure home for the admin user
            # Home Manager configuration is now in nixoa-vm/modules/home/home.nix
            users.${userArgs.username or "xoa"} = import ./modules/home/home.nix;
          };
        }

        # Provide module arguments via _module.args
        # Config data goes here (follows NixOS 25.11 best practices)
        {
          _module.args = {
            inherit xoTomlData;
          };
        }
      ];

      # Provide flake-pinned sources to modules via specialArgs
      # These are source code references that should not be overridden by module system
      # Also merge user-specific args (username, nixoaCfg, etc.) from user-config
      specialArgs = {
        inherit xoSrc libvhdiSrc;
      } // userArgs;
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

          # Get configured hostname for rebuild command
          CONFIG_DIR="/etc/nixos/nixoa/user-config"
          HOSTNAME=$(grep "hostname = " "''${CONFIG_DIR}/configuration.nix" 2>/dev/null | sed 's/.*= *"\(.*\)".*/\1/' | head -1)
          HOSTNAME="''${HOSTNAME:-nixoa}"
          echo "📦 To rebuild: cd /etc/nixos/nixoa/nixoa-vm && sudo nixos-rebuild switch --flake .#''${HOSTNAME}"
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
        echo "  nix run .#update-xo                      - Update XO source"
        echo "  sudo nixos-rebuild switch --flake .#<hostname> - Deploy changes"
        echo "  sudo nixos-rebuild test --flake .#<hostname>   - Test changes"
        echo "  nix flake check                          - Validate flake"
        echo "  nix flake show                           - Show flake outputs"
        echo ""
        echo "📝 Note: Replace <hostname> with your configured hostname (default: nixoa)"
        echo "    You can set hostname in configuration.nix (systemSettings.hostname = \"myhost\")"
        echo ""
        echo "📁 Module organization:"
        echo "  ./modules/core/     - System modules (users, network, packages, services)"
        echo "  ./modules/xo/       - XO-specific modules (xoa, storage, autocert, etc.)"
        echo "  ./modules/home/     - Home Manager configuration"
        echo "  ./modules/bundle.nix - Dynamic module discovery"
        echo ""
        echo "📝 Configuration:"
        echo "  Edit /etc/nixos/nixoa/user-config/configuration.nix to customize"
        echo ""
      '';
    };
  };
}
