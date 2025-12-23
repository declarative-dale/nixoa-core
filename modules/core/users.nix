# SPDX-License-Identifier: Apache-2.0
# User and group management, SSH configuration, security, and sudo

{ config, pkgs, lib, systemSettings ? {}, userSettings ? {}, ... }:

let
  # Safe attribute access with defaults
  get = path: default:
    let
      getValue = cfg: pathList:
        if pathList == []
        then cfg
        else if builtins.isAttrs cfg && builtins.hasAttr (builtins.head pathList) cfg
        then getValue cfg.${builtins.head pathList} (builtins.tail pathList)
        else null;
      result = getValue systemSettings path;
    in
      if result == null then default else result;

  # Extract commonly used values
  username = get ["username"] "xoa";
  sshKeys = get ["sshKeys"] [];
  extrasEnable = userSettings.extras.enable or false;
  xoServiceUser = get ["xo" "service" "user"] "xo";
  xoServiceGroup = get ["xo" "service" "group"] "xo";
in
{
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
    # Shell selection based on extras.enable in configuration.nix
    # extras.enable=false → bash (default), extras.enable=true → zsh
    shell = if extrasEnable then pkgs.zsh else pkgs.bashInteractive;
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
}
