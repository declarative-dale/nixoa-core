{ config, pkgs, lib, ... }:

{
  imports = [
    ./xen-orchestra.nix
    ./libvhdi.nix
    ./users.nix
    # (any other modules you maintain)
  ];
  # Locale warnings in your logs: make them consistent
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
  };

  ########################################
  # Xen Orchestra from source (pinned)
  ########################################
  xoa.xo = {
    enable   = true;
    ssl.enable = true;
    ssl.dir  = "/etc/ssl/xo";
    ssl.key  = "/etc/ssl/xo/key.pem";
    ssl.cert = "/etc/ssl/xo/certificate.pem";
  };
  # Sudo: NOPASSWD for 'xoa'
  security.sudo = {
    enable = true;
    # Keep wheel members needing a password by default…
    wheelNeedsPassword = true;
    # …but grant passwordless sudo to 'xoa' only
    extraRules = [
      {
        users = [ "xoa" ];
        commands = [
          { command = "ALL"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];
    };
  # Bootloader (leave as provided by user)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Xen guest agent (leave as provided by user)
  systemd.packages = [ pkgs.xen-guest-agent ];
  systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];

  #### System-wide settings moved here ####

  # Enable flakes/Nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.hostName = "xoa";
  # OpenSSH: keys-only access
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;        # toggle to false if you want keys-only
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      # Optional: restrict SSH logins to just 'xoa'
      AllowUsers = [ "xoa" ];
    };
  };

  # Networking / firewall (XO web ports)
  networking.firewall.allowedTCPPorts = [ 80 443 3389 5900 8012 ];

  # Filesystem helpers for NFS/SMB remotes (system-wide capability) :contentReference[oaicite:3]{index=3}
  boot.supportedFilesystems = [ "nfs" "cifs" ];
  # Run vhdimount as non-root user
  programs.fuse.userAllowOther = true;

  # Garbage collection & auto-updates (moved from updates.nix)
  nix.gc = {
    automatic = true;
    dates     = "daily";
    options   = "--delete-older-than 7d";
  };

  #system.autoUpgrade = {
  #  enable       = false;
  #  flake        = ".#xoa";
  #  allowReboot  = false;
  #  frequency    = "daily";
  #  schedule     = "04:00";
  #  flags        = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
  #};

  # Lock defaults appropriate to this install and silence the warning. :contentReference[oaicite:4]{index=4}
  system.stateVersion = "25.05";
}
