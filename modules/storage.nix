{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption types mkIf;
  cfg = config.xoa.storage;
  xoUser = config.xoa.xo.user or "xo";
in
{
  options.xoa.storage = {
    nfs.enable  = mkEnableOption "NFS client support";
    cifs.enable = mkEnableOption "CIFS/SMB client support";
    mountsDir   = mkOption { type = types.path; default = "/var/lib/xo/mounts"; };
  };

  config = {
    environment.systemPackages = lib.optionals cfg.nfs.enable  [ pkgs.nfs-utils ]
                              ++ lib.optionals cfg.cifs.enable [ pkgs.cifs-utils ];

    # FUSE baseline for user mounts
    programs.fuse.userAllowOther = true;
    boot.kernelModules = [ "fuse" ];

    # Minimal sudo rules for the xo user to mount/umount
    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
      extraRules = [
        {
          users = [ xoUser ];
          commands = [
            { command = "${pkgs.util-linux}/bin/mount";  options = [ "NOPASSWD" ]; }
            { command = "${pkgs.util-linux}/bin/umount"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];
    };

    # Where XO will mount remotes
    systemd.tmpfiles.rules = [
      "d ${cfg.mountsDir} 0750 ${xoUser} ${config.xoa.xo.group} - -"
      # Ensure /dev/fuse is accessible
      "c /dev/fuse 0666 root root - 10:229"
    ];
  };
}
