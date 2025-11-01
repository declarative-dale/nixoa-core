{ config, pkgs, lib, ... }:

{
  # Bootloader (leave as provided by user)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Xen guest agent (leave as provided by user)
  systemd.packages = [ pkgs.xen-guest-agent ];
  systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];

  #### System-wide settings moved here ####

  # Enable flakes/Nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # SSH daemon (system-wide)
  services.openssh = {
    enable = true;
    # Open SSH port in firewall explicitly (default also opens it automatically).
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;     # preserved from your previous users.nix
      KbdInteractiveAuthentication = false;
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

  system.autoUpgrade = {
    enable       = false;
    flake        = ".#xoa";
    allowReboot  = false;
    frequency    = "daily";
    schedule     = "04:00";
    flags        = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
  };

  # Lock defaults appropriate to this install and silence the warning. :contentReference[oaicite:4]{index=4}
  system.stateVersion = "25.05";
}
