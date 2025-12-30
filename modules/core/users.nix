# SPDX-License-Identifier: Apache-2.0
# User and group management, SSH configuration, security, and sudo

{ config, pkgs, lib, nixoaUtils, ... }:

let
  inherit (lib) mkOption types mkEnableOption;
  inherit (nixoaUtils) getOption;

  # Extract commonly used values
  username = config.nixoa.admin.username;
  sshKeys = config.nixoa.admin.sshKeys;
  shell = config.nixoa.admin.shell;
  xoServiceUser = config.nixoa.xo.service.user;
  xoServiceGroup = config.nixoa.xo.service.group;
in
{
  options.nixoa = {
    admin = {
      username = mkOption {
        type = types.str;
        default = "xoa";
        description = "Admin user username for SSH access and system administration";
      };
      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "SSH public keys authorized for admin user";
        example = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample user@example.com" ];
      };
      shell = mkOption {
        type = types.enum ["bash" "zsh"];
        default = "bash";
        description = "Login shell for admin user (bash or zsh)";
      };
    };
    xo.service = {
      user = mkOption {
        type = types.str;
        default = "xo";
        description = "System user that runs xo-server";
      };
      group = mkOption {
        type = types.str;
        default = "xo";
        description = "System group for xo-server";
      };
    };
  };

  config = {
    # ============================================================================
    # USER ACCOUNTS
    # ============================================================================

    # Primary group for XO service
    users.groups.${xoServiceGroup} = {};
    users.groups.fuse = {};

    # XO service account (runs xo-server and related services)
    users.users.${xoServiceUser} = {
      isSystemUser = true;
      description = "Xen Orchestra service account";
      createHome = true;
      group = xoServiceGroup;
      home = "/var/lib/xo";
      shell = lib.mkDefault "${pkgs.shadow}/bin/nologin";
      extraGroups = [ "fuse" ];
    };

    # XOA admin account: SSH-key login only, sudo-capable
    users.users.${username} = {
      isNormalUser = true;
      description = "Xen Orchestra Administrator";
      createHome = true;
      home = "/home/${username}";
      # Shell selection based on admin.shell option
      shell = if shell == "zsh" then pkgs.zsh else pkgs.bashInteractive;
      extraGroups = [ "wheel" "systemd-journal" ];

      # Locked password - SSH key authentication only
      hashedPassword = "!";

      openssh.authorizedKeys.keys = sshKeys;

      # User packages are now managed by Home Manager
      # (removed packages attribute - see nixoa-vm/modules/home/home.nix)
    };

    # ============================================================================
    # SECURITY & SUDO
    # ============================================================================

    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;

      extraRules = [
        # Admin user with full sudo access
        {
          users = [ username ];
          commands = [
            { command = "ALL"; options = [ "NOPASSWD" ]; }
          ];
        }

        # Note: XO service account sudo rules are configured in storage.nix
        # to avoid duplication and ensure all mount/vhd operations are covered
      ];
    };

    # System limits
    security.pam.loginLimits = [
      {
        domain = xoServiceUser;
        type = "soft";
        item = "nofile";
        value = "65536";
      }
      {
        domain = xoServiceUser;
        type = "hard";
        item = "nofile";
        value = "1048576";
      }
    ];

    # ============================================================================
    # SSH SERVICE
    # ============================================================================

    services.openssh = {
      enable = true;
      openFirewall = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
        AllowUsers = [ username ];

        # Security hardening
        X11Forwarding = false;
        PermitEmptyPasswords = false;
        Protocol = 2;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
      };

      # Host keys (let sshd generate them on first boot)
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
    };
  };
}
