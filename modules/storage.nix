{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption types mkIf;
  cfg = config.xoa.storage;
  xoUser = config.xoa.xo.user or "xo";
  xoGroup = config.xoa.xo.group or "xo";
  
  # Safe mount wrapper that restricts what the xo user can mount
  mountWrapper = pkgs.writeShellScript "xo-mount-helper" ''
    set -euo pipefail
    
    # Usage: xo-mount-helper <type> <source> <target> [options...]
    FSTYPE="$1"
    SOURCE="$2"
    TARGET="$3"
    shift 3
    
    # Validate mount point is under allowed directory
    case "$TARGET" in
      ${cfg.mountsDir}/*)
        # OK - under allowed directory
        ;;
      *)
        echo "Error: Mount point must be under ${cfg.mountsDir}" >&2
        echo "Attempted: $TARGET" >&2
        exit 1
        ;;
    esac
    
    # Only allow NFS/CIFS filesystem types
    case "$FSTYPE" in
      nfs|nfs4|cifs)
        exec ${pkgs.util-linux}/bin/mount -t "$FSTYPE" "$SOURCE" "$TARGET" "$@"
        ;;
      *)
        echo "Error: Only NFS and CIFS mounts allowed, got: $FSTYPE" >&2
        exit 1
        ;;
    esac
  '';
  
  # Safe umount wrapper
  umountWrapper = pkgs.writeShellScript "xo-umount-helper" ''
    set -euo pipefail
    
    TARGET="$1"
    
    # Validate mount point is under allowed directory
    case "$TARGET" in
      ${cfg.mountsDir}/*)
        exec ${pkgs.util-linux}/bin/umount "$TARGET"
        ;;
      *)
        echo "Error: Can only unmount under ${cfg.mountsDir}" >&2
        echo "Attempted: $TARGET" >&2
        exit 1
        ;;
    esac
  '';
in
{
  options.xoa.storage = {
    nfs.enable  = mkEnableOption "NFS client support";
    cifs.enable = mkEnableOption "CIFS/SMB client support";
    mountsDir   = mkOption { 
      type = types.path; 
      default = "/var/lib/xo/mounts";
      description = "Base directory for XO remote storage mounts";
    };
  };

  config = mkIf (cfg.nfs.enable || cfg.cifs.enable) {
    # Install required filesystem tools
    environment.systemPackages = lib.optionals cfg.nfs.enable  [ pkgs.nfs-utils ]
                              ++ lib.optionals cfg.cifs.enable [ pkgs.cifs-utils ];

    # FUSE support for user mounts
    programs.fuse.userAllowOther = true;
    boot.kernelModules = [ "fuse" ];

    # Restricted sudo rules using safe wrappers
    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
      extraRules = [
        {
          users = [ xoUser ];
          commands = [
            { 
              command = "${mountWrapper}";
              options = [ "NOPASSWD" "SETENV" ];
            }
            { 
              command = "${umountWrapper}";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    # Create mount directory
    # Note: /dev/fuse is created automatically by the kernel when the fuse
    # module loads, so we don't need to create it via tmpfiles
    systemd.tmpfiles.rules = [
      "d ${cfg.mountsDir} 0750 ${xoUser} ${xoGroup} - -"
    ];
    
    # Ensure xo user is in fuse group (already done in xoa.nix, but good to be explicit)
    assertions = [
      {
        assertion = builtins.elem "fuse" config.users.users.${xoUser}.extraGroups;
        message = "XO user must be in 'fuse' group for remote storage mounting";
      }
    ];
  };
}