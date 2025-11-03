{ config, pkgs, lib, ... }:

{
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
    user     = "xo";
    group    = "xo";
    home     = "/home/xo";
    appDir   = "/var/lib/xo/app";
    cacheDir = "/var/cache/xo/yarn-cache";
    StateDirectory = "xo";         # -> /var/lib/xo (created/owned for the service)
    CacheDirectory = "xo";         # -> /var/cache/xo
    StateDirectoryMode = "0750";
    CacheDirectoryMode = "0750";

    # Pin to your desired commit
    srcRev  = "2dd451a7d933f27e550fac673029d8ab79aba70d";
    srcHash = "sha256-TpXyd7DohHG50HvxzfNmWVtiW7BhGSxWk+3lgFMMf/M=";

    # HTTPS + redis
    host     = "0.0.0.0";
    port     = 443;
    redisUrl = "redis://127.0.0.1:6379/0";

    ssl.enable = true;
    ssl.dir  = "/etc/ssl/xo";
    ssl.key  = "/etc/ssl/xo/key.pem";
    ssl.cert = "/etc/ssl/xo/certificate.pem";
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
  # SSH daemon (system-wide)
  services.openssh = {
    enable = true;
    # Open SSH port in firewall explicitly (default also opens it automatically).
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;        # toggle to false if you want keys-only
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
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
