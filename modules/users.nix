{ config, pkgs, lib, ... }:

{
  # Primary group for xo; ensures chown root:xo and tmpfiles rules work.
  users.groups.xo = {};
  users.users.xo = {
    isSystemUser   = true;
    description    = "Xen Orchestra service account";
    createHome     = true;
    group          = "xo";
    home           = "/var/lib/xo";
    shell          = "/run/current-system/sw/bin/nologin";
  };
 # XenOrchestra admin: SSH-key login only, sudo-capable
 users.users.xoa = {
   isNormalUser   = true;
   description    = "XenOrchestra admin (SSH-only)";
   createHome     = true;
   home           = "/home/xoa";
   shell          = pkgs.bashInteractive;
   extraGroups    = [ "wheel" "systemd-journal" ];
   hashedPassword = "!";
   openssh.authorizedKeys.keys = [
     "ssh-ed25519 AAAA... xoa@yourhost"
   ];
 };
}
