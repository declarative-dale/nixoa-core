{ config, pkgs, lib, ... }:

{
  imports = [
    ./xen-orchestra.nix
    # (any other modules you maintain)
  ];

  # Make sure the xo user exists (example)
  users.users.xo = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # your ssh pubkey(s)
    ];
  };
  users.groups.xo = { };

  # Your XO from sources, pinned to the rev you asked for
  xoa.xo = {
    enable  = true;
    user    = "xo";
    group   = "xo";
    buildDir = "/var/lib/xo";
    tls.commonName = "xoa.internal";

    # Pin to your requested commit:
    srcRev  = "2dd451a7d933f27e550fac673029d8ab79aba70d";

    # Fill in the correct SRI for that rev (placeholder shown):
    # Compute with:
    #   nix run nixpkgs#nix-prefetch-github -- vatesfr xen-orchestra --rev 2dd451a7d933f27e550fac673029d8ab79aba70d
    # Then convert to SRI if needed: nix hash to-sri --type sha256 <hex>
    srcHash = "sha256-TpXyd7DohHG50HvxzfNmWVtiW7BhGSxWk+3lgFMMf/M=";

    http.port  = 80;
    https.port = 443;
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
