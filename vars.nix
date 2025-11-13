# vars.nix
{
  # ===== Editable variables =====
  system   = "x86_64-linux";
  hostname = "xoa";                         # nixosConfigurations.${hostname}
  username = "xoa";                         # admin login user (sudoer)
  sshKeys  = [
    # paste one or more public keys here
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@email"
  ];

  # Xen Orchestra
  xoHost      = "0.0.0.0";
  xoPort      = 80;
  xoHttpsPort = 443;
  tls = {
    enable    = true;
    dir       = "/etc/ssl/xo";
    cert      = "/etc/ssl/xo/certificate.pem";
    key       = "/etc/ssl/xo/key.pem";
  };

  # Storage / mounts
  storage = {
    nfs.enable  = true;
    cifs.enable = true;
    mountsDir   = "/var/lib/xo/mounts";
  };
  # Where your local git clone of this flake lives on the machine.
  # The auto-updaters and GC timers will run *inside* this directory.
  updates = {
    repoDir = "~/declarative-xoa-ce";

    # Standalone GC with “keep N successful system generations”
    gc = {
      enable = false;
      schedule = "Sun 04:00";
      keepGenerations = 7;
    };

    # Update nixpkgs input + rebuild
    nixos = {
      enable = false;
      schedule = "Sun 04:00";
    };

    # Pull latest commits from the flake’s remote (Codeberg) but keep your vars.nix intact
    flake = {
      enable = false;
      schedule = "Sun 04:00";
      remoteUrl = "https://codeberg.org/dalemorgan/declarative-xoa-ce.git";
      branch = "main";
      protectPaths = [ "vars.nix" ];
    };

    # Update XO upstream input (xoSrc) + rebuild
    xoa = {
      enable = false;
      schedule = "Sun 04:00";
    };
  };
  # ===== Advanced (usually leave alone) =====
  xoUser  = "xo";                            # XO service user
  xoGroup = "xo";
  stateVersion = "25.05";
}
