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
  };

  outputs = { self, nixpkgs, home-manager, xoSrc, libvhdiSrc, ... }:
  let
    # System architecture (cannot be overridden by modules)
    system = "x86_64-linux";
    lib = nixpkgs.lib;

    # Only import pkgs where needed (for packages/apps/devShells)
    pkgs = nixpkgs.legacyPackages.${system};

    # Import utility library for modules
    utils = import ./lib/utils.nix { inherit lib; };
  in {
    # Package outputs - XOA and libvhdi built from source
    packages.${system} = {
      xo-ce = pkgs.callPackage ./pkgs/xo-ce { inherit xoSrc; };
      libvhdi = pkgs.callPackage ./pkgs/libvhdi { inherit libvhdiSrc; };
      default = self.packages.${system}.xo-ce;

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

    # Overlay for easy nixpkgs extension
    # Usage: overlays.default (adds nixoa.xo-ce and nixoa.libvhdi to pkgs)
    overlays.default = final: prev: {
      nixoa = {
        xo-ce = self.packages.${system}.xo-ce;
        libvhdi = self.packages.${system}.libvhdi;
      };
    };

    # Module library export - nixoa-vm is a module provider for user-config
    # Usage in user-config: nixoa-vm.nixosModules.default
    nixosModules.default = { config, lib, pkgs, ... }: {
      imports = [
        # Auto-import all modules EXCEPT home/ (handled separately in user-config)
        ./modules
      ];

      # Make packages and utilities available to all modules
      _module.args = {
        nixoaPackages = self.packages.${system};
        nixoaUtils = utils;
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
          echo ""
          echo "📦 To rebuild with nixoa-vm updates:"
          echo "   cd ~/user-config && sudo nixos-rebuild switch --flake ."
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
        echo "║     NixOA-VM Module Library Development Environment       ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "📋 This is the nixoa-vm module library (immutable, git-managed)"
        echo ""
        echo "📁 Module organization:"
        echo "  ./modules/core/     - System modules (users, network, packages, services)"
        echo "  ./modules/xo/       - XO-specific modules (xoa, storage, autocert, etc.)"
        echo "  ./modules/bundle.nix - Dynamic module discovery (excludes home/)"
        echo ""
        echo "📝 Available commands:"
        echo "  nix run .#update-xo                - Update XO source code"
        echo "  nix flake check                    - Validate flake"
        echo "  nix flake show                     - Show flake outputs"
        echo ""
        echo "⚙️  Module usage:"
        echo "  user-config imports this as: nixoa-vm.nixosModules.default"
        echo "  System rebuilds from ~/user-config: cd ~/user-config && sudo nixos-rebuild switch --flake ."
        echo ""
        echo "📝 Configuration files are in ~/user-config (not here)"
        echo "  Edit ~/user-config/configuration.nix to customize settings"
        echo ""
      '';
    };
  };
}
