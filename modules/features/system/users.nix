# SPDX-License-Identifier: Apache-2.0
# User and group management, SSH configuration, security, and sudo

{
  config,
  pkgs,
  lib,
  nixoaUtils,
  vars,
  ...
}:

{
  config = {
    # ============================================================================
    # USER ACCOUNTS
    # ============================================================================

    # Ensure .ssh directory exists with correct permissions before NixOS creates authorized_keys
    systemd.tmpfiles.rules = [
      "d /home/${vars.username}/.ssh 0700 ${vars.username} users -"
    ];

    # Primary group for XO service
    users.groups.${vars.xoGroup} = { };
    users.groups.fuse = { };

    # XO service account (runs xo-server and related services)
    users.users.${vars.xoUser} = {
      isSystemUser = true;
      description = "Xen Orchestra service account";
      createHome = true;
      group = vars.xoGroup;
      home = "/var/lib/xo";
      shell = lib.mkDefault "${pkgs.shadow}/bin/nologin";
      extraGroups = [ "fuse" ];
    };

    # XOA admin account: SSH-key login only, sudo-capable
    users.users.${vars.username} = {
      isNormalUser = true;
      description = "Xen Orchestra Administrator";
      createHome = true;
      home = "/home/${vars.username}";
      # Shell selection: zsh when extras enabled, bash otherwise
      shell = if vars.enableExtras then pkgs.zsh else pkgs.bashInteractive;
      extraGroups = [
        "wheel"
        "systemd-journal"
      ];

      # Locked password - SSH key authentication only
      hashedPassword = "!";

      # SSH keys managed at NixOS level (supports multiple keys as list)
      openssh.authorizedKeys.keys = vars.sshKeys;

      # User packages are now managed by Home Manager
      # (removed packages attribute - see system/modules/home.nix in user-config)
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
          users = [ vars.username ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }

        # Note: XO service account sudo rules are configured in storage.nix
        # to avoid duplication and ensure all mount/vhd operations are covered
      ];
    };

    # System limits
    security.pam.loginLimits = [
      {
        domain = vars.xoUser;
        type = "soft";
        item = "nofile";
        value = "65536";
      }
      {
        domain = vars.xoUser;
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
        AllowUsers = [ vars.username ];

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
