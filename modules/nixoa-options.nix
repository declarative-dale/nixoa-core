# SPDX-License-Identifier: Apache-2.0
# NixOA Options Definitions
# ==============================================================================
# This module defines the complete options.nixoa.* namespace for NixOA.
# These options provide a type-safe, declarative interface for configuring
# the NixOA system. Values are provided by user-config flake.
# ==============================================================================

{ lib, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.nixoa = {
    # ==========================================================================
    # SYSTEM IDENTIFICATION
    # ==========================================================================

    # NOTE: No 'system' option here - that's determined by flake.nix
    # Modules cannot override the flake-level system architecture

    hostname = mkOption {
      type = types.str;
      example = "nixoa";
      description = "Hostname for the NiXOA system.";
    };

    stateVersion = mkOption {
      type = types.str;
      default = "25.11";
      description = ''
        NixOS state version for this system.
        DO NOT CHANGE this value after initial installation.
      '';
    };

    # ==========================================================================
    # ADMIN USER CONFIGURATION
    # ==========================================================================

    admin = {
      username = mkOption {
        type = types.str;
        example = "xoa";
        description = "Primary admin user for XO access.";
      };

      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample... user@host" ];
        description = ''
          SSH public keys authorized for the admin user.
          The admin user can only authenticate via SSH keys (no password).
        '';
      };
    };

    # ==========================================================================
    # XEN ORCHESTRA CONFIGURATION
    # ==========================================================================

    xo = {
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = ''
          Bind address for XO server.
          Use "0.0.0.0" to listen on all interfaces, or a specific IP for restricted access.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 80;
        description = "XO HTTP port (used when TLS is disabled or for HTTP→HTTPS redirect).";
      };

      httpsPort = mkOption {
        type = types.port;
        default = 443;
        description = "XO HTTPS port (when TLS is enabled).";
      };

      service = {
        user = mkOption {
          type = types.str;
          default = "xo";
          description = "Unix user running XO processes.";
        };

        group = mkOption {
          type = types.str;
          default = "xo";
          description = "Unix group owning XO resources.";
        };
      };

      tls = {
        enable = mkEnableOption "TLS/HTTPS support for XO" // { default = true; };

        redirectToHttps = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Redirect HTTP traffic to HTTPS when TLS is enabled.
            Allows HTTP connections only for the redirect.
          '';
        };

        autoGenerate = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Automatically generate self-signed certificates if cert/key don't exist.
            Useful for quick setup, but consider using proper certificates in production.
          '';
        };

        dir = mkOption {
          type = types.str;  # Runtime filesystem path, not Nix store path
          default = "/etc/ssl/xo";
          description = "Directory for TLS certificates.";
        };

        cert = mkOption {
          type = types.str;  # Runtime filesystem path, not Nix store path
          default = "/etc/ssl/xo/certificate.pem";
          description = "Path to TLS certificate file.";
        };

        key = mkOption {
          type = types.str;  # Runtime filesystem path, not Nix store path
          default = "/etc/ssl/xo/key.pem";
          description = "Path to TLS private key file.";
        };
      };
    };

    # ==========================================================================
    # STORAGE CONFIGURATION
    # ==========================================================================

    storage = {
      nfs.enable = mkEnableOption "NFS remote storage support" // { default = true; };
      cifs.enable = mkEnableOption "CIFS/SMB remote storage support" // { default = true; };
      vhd.enable = mkEnableOption "VHD support via libvhdi" // { default = true; };

      mountsDir = mkOption {
        type = types.str;  # Runtime filesystem path, not Nix store path
        default = "/var/lib/xo/mounts";
        description = ''
          Base directory where XO creates remote mounts.
          Subdirectories are created automatically for each storage backend.
        '';
      };
    };

    # ==========================================================================
    # NETWORKING
    # ==========================================================================

    networking = {
      firewall = {
        allowedTCPPorts = mkOption {
          type = types.listOf types.port;
          default = [ 80 443 3389 5900 8012 ];
          description = ''
            TCP ports to open in the firewall.
            Default includes: HTTP (80), HTTPS (443), RDP (3389), VNC (5900), noVNC (8012).
          '';
        };
      };
    };

    # ==========================================================================
    # TIMEZONE
    # ==========================================================================

    timezone = mkOption {
      type = types.str;
      default = "UTC";
      example = "America/New_York";
      description = "System timezone.";
    };

    # ==========================================================================
    # PACKAGES
    # ==========================================================================

    packages = {
      system.extra = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "vim" "git" "htop" "btop" ];
        description = ''
          Extra system-wide packages to install (nixpkgs attribute names).
          These packages are available to all users.
        '';
      };

      user.extra = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "neovim" "tmux" "zsh" ];
        description = ''
          Extra packages installed for the admin user only.
          Uses nixpkgs attribute names.
        '';
      };
    };

    # ==========================================================================
    # CUSTOM SERVICES
    # ==========================================================================

    services = {
      definitions = mkOption {
        type = types.attrsOf (types.attrsOf types.anything);
        default = {};
        example = {
          docker = { enable = true; enableOnBoot = true; };
          tailscale = { enable = true; useRoutingFeatures = "both"; };
        };
        description = ''
          Custom NixOS service configurations.
          These are merged into config.services in system.nix.

          Can be used to enable and configure NixOS services with specific options.
        '';
      };
    };

    # ==========================================================================
    # TERMINAL EXTRAS
    # ==========================================================================

    extras = {
      enable = mkEnableOption "Enhanced terminal experience (zsh + tools)" // {
        default = false;
      };
    };

    # ==========================================================================
    # UPDATES CONFIGURATION
    # ==========================================================================

    updates = {
      repoDir = mkOption {
        type = types.str;
        default = "/etc/nixos/nixoa/nixoa-vm";
        description = ''
          Path to the NixOA flake repository.
          Supports tilde expansion (~/path).
        '';
      };

      # Monitoring and notifications
      monitoring = {
        notifyOnSuccess = mkOption {
          type = types.bool;
          default = false;
          description = "Send notifications even for successful update runs.";
        };

        email = {
          enable = mkEnableOption "Email notifications for updates";
          to = mkOption {
            type = types.str;
            default = "admin@example.com";
            description = "Email address for update notifications.";
          };
        };

        ntfy = {
          enable = mkEnableOption "ntfy.sh notifications for updates";
          server = mkOption {
            type = types.str;
            default = "https://ntfy.sh";
            description = "ntfy server URL.";
          };
          topic = mkOption {
            type = types.str;
            default = "xoa-updates";
            description = "ntfy topic name for update notifications.";
          };
        };

        webhook = {
          enable = mkEnableOption "Webhook notifications for updates";
          url = mkOption {
            type = types.str;
            default = "";
            description = "Webhook URL to POST update notifications to.";
          };
        };
      };

      # Garbage collection
      gc = {
        enable = mkEnableOption "Automatic garbage collection";
        schedule = mkOption {
          type = types.str;
          default = "Sun 04:00";
          description = ''
            Systemd timer schedule for garbage collection.
            Uses systemd.time(7) format (e.g., "Sun 04:00", "daily").
          '';
        };
        keepGenerations = mkOption {
          type = types.int;
          default = 7;
          description = "Number of generations to keep during GC.";
        };
      };

      # Flake updates
      flake = {
        enable = mkEnableOption "Automatic flake updates";
        schedule = mkOption {
          type = types.str;
          default = "Sun 04:00";
          description = "Systemd timer schedule for flake updates.";
        };
        remoteUrl = mkOption {
          type = types.str;
          default = "https://codeberg.org/nixoa/nixoa-vm.git";
          description = "Remote repository URL to pull flake updates from.";
        };
        branch = mkOption {
          type = types.str;
          default = "main";
          description = "Git branch to track for updates.";
        };
        autoRebuild = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Automatically rebuild the system after flake updates.
            If false, updates are fetched but not applied until manual rebuild.
          '';
        };
      };

      # NixOS channel/nixpkgs updates
      nixpkgs = {
        enable = mkEnableOption "Automatic nixpkgs updates";
        schedule = mkOption {
          type = types.str;
          default = "Mon 04:00";
          description = "Systemd timer schedule for nixpkgs updates.";
        };
        keepGenerations = mkOption {
          type = types.int;
          default = 7;
          description = "Number of generations to keep after nixpkgs updates.";
        };
      };

      # Xen Orchestra updates
      xoa = {
        enable = mkEnableOption "Automatic XO updates";
        schedule = mkOption {
          type = types.str;
          default = "Tue 04:00";
          description = "Systemd timer schedule for XO source updates.";
        };
        keepGenerations = mkOption {
          type = types.int;
          default = 7;
          description = "Number of generations to keep after XO updates.";
        };
      };

      # libvhdi library updates
      libvhdi = {
        enable = mkEnableOption "Automatic libvhdi updates";
        schedule = mkOption {
          type = types.str;
          default = "Wed 04:00";
          description = "Systemd timer schedule for libvhdi updates.";
        };
        keepGenerations = mkOption {
          type = types.int;
          default = 7;
          description = "Number of generations to keep after libvhdi updates.";
        };
      };
    };
  };
}
