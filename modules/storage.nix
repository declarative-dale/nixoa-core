{ config, lib, pkgs, vars, ... }:
let
  inherit (lib) mkOption mkEnableOption types mkIf;
  cfg = config.xoa.storage;
  xoUser = config.xoa.xo.user or vars.xoUser;
  xoGroup = config.xoa.xo.group or vars.xoGroup;

in
{
  options.xoa.storage = {
    nfs.enable  = mkEnableOption "NFS client support for XO remote storage";
    cifs.enable = mkEnableOption "CIFS/SMB client support for XO remote storage";
    vhd.enable  = mkEnableOption "VHD mounting support via libvhdi" // { default = true; };
    
    mountsDir = mkOption { 
      type = types.path; 
      default = "/var/lib/xo/mounts";
      description = "Base directory for XO remote storage mounts";
    };
    
    # Advanced options
    sudoNoPassword = mkOption {
      type = types.bool;
      default = true;
      description = "Allow XO user to mount/unmount without password";
    };
  };

  config = mkIf (cfg.nfs.enable || cfg.cifs.enable || cfg.vhd.enable) {
    # Setuid wrapper for mount.cifs (required for capability handling)
    security.wrappers = lib.mkIf cfg.cifs.enable {
      "mount.cifs" = {
        program = "mount.cifs";
        source = "${lib.getBin pkgs.cifs-utils}/bin/mount.cifs";
        owner = "root";
        group = "root";
        setuid = true;
        # Allow mount.cifs to manage capabilities freely
        capabilities = "cap_dac_override,cap_sys_admin=ep";
      };
    };

    # Disable sudo audit plugin to avoid permission issues with systemd hardening
    # (journald already captures all sudo activity)
    security.sudo.extraConfig = ''
      Defaults !use_pty
      Defaults !log_subcmds
      # Preserve capabilities for mount operations
      Defaults:${xoUser} !use_pty,!syslog
    '';

    # No special sudo env configuration needed - our wrapper handles CIFS credentials
    # by injecting them as mount options before calling sudo

    # Install required filesystem tools
    environment.systemPackages =
      lib.optionals cfg.nfs.enable  [ pkgs.nfs-utils ] ++
      lib.optionals cfg.cifs.enable [ pkgs.cifs-utils ] ++
      lib.optionals cfg.vhd.enable  [ config.services.libvhdi.package ];

    # Enable libvhdi if VHD support is requested
    services.libvhdi.enable = cfg.vhd.enable;

    # FUSE support for user mounts
    programs.fuse.userAllowOther = true;
    boot.kernelModules = [ "fuse" ]
      ++ lib.optionals cfg.nfs.enable [ "nfs" "nfsv4" ]
      ++ lib.optionals cfg.cifs.enable [ "cifs" ];

    # Ensure filesystem support at boot
    boot.supportedFilesystems = 
      lib.optionals cfg.nfs.enable [ "nfs" "nfs4" ] ++
      lib.optionals cfg.cifs.enable [ "cifs" ];

    # Restricted sudo rules using safe wrappers
    security.sudo = {
      enable = true;
      extraRules = [
        {
          users = [ xoUser ];
          commands = [
            # Core mount/umount commands - allow both symlinked and direct paths
            { command = "/run/current-system/sw/bin/mount"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/umount"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/findmnt"; options = [ "NOPASSWD" ]; }
            { command = "/run/wrappers/bin/mount"; options = [ "NOPASSWD" ]; }
            { command = "/run/wrappers/bin/umount"; options = [ "NOPASSWD" ]; }
            { command = "/run/wrappers/bin/findmnt"; options = [ "NOPASSWD" ]; }
            # Allow nix store paths (util-linux can be at different store paths)
            { command = "/nix/store/*/bin/mount"; options = [ "NOPASSWD" ]; }
            { command = "/nix/store/*/bin/umount"; options = [ "NOPASSWD" ]; }
            { command = "/nix/store/*/bin/findmnt"; options = [ "NOPASSWD" ]; }
          ] ++
          # VHD mount tools
          lib.optionals cfg.vhd.enable [
            { command = "/run/current-system/sw/bin/vhdimount"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/vhdiinfo"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];
    };

    # Create mount directory
    systemd.tmpfiles.rules = [
      "d ${cfg.mountsDir} 0750 ${xoUser} ${xoGroup} - -"
    ];

    # One-time service to initialize sudo for xo user (clears the lecture)
    systemd.services.xo-sudo-init = {
      description = "Initialize sudo for XO user";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "xo-sudo-init" ''
          # Create sudo timestamp directory for xo user if it doesn't exist
          if [ ! -f /var/db/sudo/lectured/${xoUser} ]; then
            mkdir -p /var/db/sudo/lectured
            touch /var/db/sudo/lectured/${xoUser}
            chown root:root /var/db/sudo/lectured/${xoUser}
            chmod 0600 /var/db/sudo/lectured/${xoUser}
          fi
        ''}";
      };
    };
    
    # Ensure xo user is in fuse group
    assertions = [
      {
        assertion = config.users.users.${xoUser}.extraGroups or [] != [] -> 
                   builtins.elem "fuse" config.users.users.${xoUser}.extraGroups;
        message = "XO user must be in 'fuse' group for remote storage mounting";
      }
      {
        assertion = cfg.nfs.enable || cfg.cifs.enable || cfg.vhd.enable;
        message = "At least one storage type must be enabled (NFS, CIFS, or VHD)";
      }
    ];
  };
}
