{ config, pkgs, lib, ... }:

{
  imports = [
    ./xen-orchestra.nix
    ./libvhdi.nix
    ./users.nix
  ];

  # Locale settings
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
  };

  ########################################
  # Xen Orchestra from source (pinned)
  ########################################
  xoa.xo = {
    enable = true;
    host = "0.0.0.0";
    port = 80;
    httpsPort = 443;
    
    ssl.enable = true;
    ssl.dir = "/etc/ssl/xo";
    ssl.key = "/etc/ssl/xo/key.pem";
    ssl.cert = "/etc/ssl/xo/certificate.pem";
    
    # Data directories
    dataDir = "/var/lib/xo/data";
    tempDir = "/var/lib/xo/tmp";
    mountsDir = "/var/lib/xo/mounts";
  };

  # Sudo: NOPASSWD for 'xo' user for mounting operations
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    extraRules = [
      # XO service account needs specific mount/umount privileges
      {
        users = [ "xo" ];
        commands = [
          { command = "${pkgs.util-linux}/bin/mount"; options = [ "NOPASSWD" ]; }
          { command = "${pkgs.util-linux}/bin/umount"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/vhdimount"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/vhdiinfo"; options = [ "NOPASSWD" ]; }
          { command = "${pkgs.nfs-utils}/bin/mount.nfs"; options = [ "NOPASSWD" ]; }
          { command = "${pkgs.nfs-utils}/bin/mount.nfs4"; options = [ "NOPASSWD" ]; }
          { command = "${pkgs.cifs-utils}/bin/mount.cifs"; options = [ "NOPASSWD" ]; }
        ];
      }
      # Admin user with full sudo access (passwordless for convenience)
      {
        users = [ "xoa" ];
        commands = [
          { command = "ALL"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Xen guest agent
  systemd.packages = [ pkgs.xen-guest-agent ];
  systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];

  # Enable flakes/Nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  networking.hostName = "xoa";
  
  # OpenSSH: keys-only access
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      AllowUsers = [ "xoa" ];
    };
  };

  # Networking / firewall (XO web ports + VNC/RDP for console access)
  networking.firewall.allowedTCPPorts = [ 80 443 3389 5900 8012 ];

  # Filesystem helpers for NFS/SMB remotes (system-wide capability)
  boot.supportedFilesystems = [ "nfs" "cifs" ];
  
  # Enable FUSE for user mounts (required for vhdimount)
  programs.fuse.userAllowOther = true;

  # Ensure NFS/CIFS utilities are available
  environment.systemPackages = with pkgs; [
    nfs-utils
    cifs-utils
  ];

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # Auto-upgrade configuration (disabled by default)
  # Uncomment to enable automatic system updates
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = ".#xoa";
  #   allowReboot = false;
  #   dates = "04:00";
  #   flags = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
  # };

  # Lock to NixOS 25.05
  system.stateVersion = "25.05";
}
