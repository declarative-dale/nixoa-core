{ config, pkgs, lib, ... }:

{
  # Primary group for xo; ensures chown root:xo and tmpfiles rules work.
  users.groups.xo = {};
  users.users.xo = {
    isNormalUser   = true;
    description    = "XO admin/login user";
    createHome     = true;
    group          = "xo";
    # Set an initial password; change it on first login: passwd xo
    initialPassword = "xo";
    extraGroups    = [ "wheel" "systemd-journal" ];
    shell          = pkgs.bashInteractive;
    # --- Add your SSH public keys here ---
    # Option A: inline keys
    openssh.authorizedKeys.keys = [
      # Replace with your real public key(s):
      "ssh-ed25519 123456"
      # You can add more keys as needed
      # "ssh-rsa AAAAB3Nz... another-key"
    ];

  };
}
