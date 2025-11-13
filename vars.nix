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

  # ===== Advanced (usually leave alone) =====
  xoUser  = "xo";                            # XO service user
  xoGroup = "xo";
  stateVersion = "25.05";
}
