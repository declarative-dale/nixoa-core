{ config, pkgs, lib, ... }:

{
  users.users.xo = {
    isNormalUser   = true;
    description    = "XO admin/login user";
    createHome     = true;
    # Set an initial password; change it on first login: passwd xo
    initialPassword = "xo";
    extraGroups    = [ "wheel" "systemd-journal" ];
  };

  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    settings.PasswordAuthentication = true;
  };
}
