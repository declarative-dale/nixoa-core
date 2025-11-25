{ config, lib, pkgs, vars, ... }:
let
  inherit (lib) mkOption mkEnableOption types mkIf;
  cfg = config.xoa.storage;
  xoUser = config.xoa.xo.user or vars.xoUser;
  xoGroup = config.xoa.xo.group or vars.xoGroup;
  
  # Safe mount wrapper that restricts what the xo user can mount
  mountWrapper = pkgs.writeShellScript "xo-mount-helper" ''
    set -euo pipefail

    # Usage: xo-mount-helper <type> <source> <target> [options...]
    if [ $# -lt 3 ]; then
      echo "Usage: $0 <type> <source> <target> [options...]" >&2
      echo "  type: nfs, nfs4, or cifs" >&2
      echo "  source: remote share path" >&2
      echo "  target: local mount point" >&2
      exit 1
    fi

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

    # Create mount point if it doesn't exist
    if [ ! -d "$TARGET" ]; then
      mkdir -p "$TARGET"
      chown ${xoUser}:${xoGroup} "$TARGET"
    fi

    # Only allow NFS/CIFS filesystem types
    case "$FSTYPE" in
      nfs|nfs4)
        if [ ! -x "${pkgs.nfs-utils}/bin/mount.nfs" ]; then
          echo "Error: NFS utilities not installed" >&2
          exit 1
        fi
        exec ${pkgs.util-linux}/bin/mount -t "$FSTYPE" "$SOURCE" "$TARGET" "$@"
        ;;
      cifs)
        if [ ! -x "${pkgs.cifs-utils}/bin/mount.cifs" ]; then
          echo "Error: CIFS utilities not installed" >&2
          exit 1
        fi
        # For CIFS, ensure USER and PASSWD env vars are preserved
        # These should already be in the environment if called with sudo -E
        exec ${pkgs.util-linux}/bin/mount -t "$FSTYPE" "$SOURCE" "$TARGET" "$@"
        ;;
      *)
        echo "Error: Only NFS and CIFS mounts allowed, got: $FSTYPE" >&2
        exit 1
        ;;
    esac
  '';

  # Mount wrapper that handles environment variables for CIFS authentication
  # This wrapper is called instead of 'mount' and properly passes credentials through sudo
  mountCommandWrapper = pkgs.writeShellScript "xo-mount-wrapper" ''
    set -euo pipefail

    # This wrapper replaces 'mount' in XO's PATH
    # When XO sets USER/PASSWD env vars via execa, this wrapper ensures they reach mount.cifs

    # Check if USER and PASSWD are set (for CIFS mounts)
    if [ -n "''${USER:-}" ] && [ -n "''${PASSWD:-}" ]; then
      # Call sudo with explicit environment variable passing
      exec /run/wrappers/bin/sudo USER="$USER" PASSWD="$PASSWD" /run/current-system/sw/bin/mount "$@"
    else
      # For non-CIFS mounts, just call mount normally
      exec /run/wrappers/bin/sudo /run/current-system/sw/bin/mount "$@"
    fi
  '';
  
  # Safe umount wrapper
  umountWrapper = pkgs.writeShellScript "xo-umount-helper" ''
    set -euo pipefail
    
    if [ $# -lt 1 ]; then
      echo "Usage: $0 <target>" >&2
      exit 1
    fi
    
    TARGET="$1"
    
    # Validate mount point is under allowed directory
    case "$TARGET" in
      ${cfg.mountsDir}/*)
        # Check if actually mounted
        if mountpoint -q "$TARGET"; then
          exec ${pkgs.util-linux}/bin/umount "$TARGET"
        else
          echo "Warning: $TARGET is not mounted" >&2
          exit 0
        fi
        ;;
      *)
        echo "Error: Can only unmount under ${cfg.mountsDir}" >&2
        echo "Attempted: $TARGET" >&2
        exit 1
        ;;
    esac
  '';
  
  # VHD mount wrapper for libvhdi integration
  vhdMountWrapper = pkgs.writeShellScript "xo-vhd-mount-helper" ''
    set -euo pipefail
    
    if [ $# -lt 2 ]; then
      echo "Usage: $0 <vhd-file> <mount-point>" >&2
      exit 1
    fi
    
    VHD_FILE="$1"
    MOUNT_POINT="$2"
    
    # Validate mount point is under allowed directory
    case "$MOUNT_POINT" in
      ${cfg.mountsDir}/*)
        # OK - under allowed directory
        ;;
      *)
        echo "Error: Mount point must be under ${cfg.mountsDir}" >&2
        echo "Attempted: $MOUNT_POINT" >&2
        exit 1
        ;;
    esac
    
    # Validate VHD file exists
    if [ ! -f "$VHD_FILE" ]; then
      echo "Error: VHD file not found: $VHD_FILE" >&2
      exit 1
    fi
    
    # Create mount point if needed
    if [ ! -d "$MOUNT_POINT" ]; then
      mkdir -p "$MOUNT_POINT"
      chown ${xoUser}:${xoGroup} "$MOUNT_POINT"
    fi
    
    # Mount with vhdimount
    exec /run/current-system/sw/bin/vhdimount -o allow_other "$VHD_FILE" "$MOUNT_POINT"
  '';
  
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
      };
    };

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
            # Core mount/umount commands
            { command = "/run/current-system/sw/bin/mount"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/umount"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/findmnt"; options = [ "NOPASSWD" ]; }
            { command = "/run/wrappers/bin/mount"; options = [ "NOPASSWD" ]; }
            { command = "/run/wrappers/bin/umount"; options = [ "NOPASSWD" ]; }
            { command = "/run/wrappers/bin/findmnt"; options = [ "NOPASSWD" ]; }
          ] ++
          # VHD mount tools
          lib.optionals cfg.vhd.enable [
            { command = "/run/current-system/sw/bin/vhdimount"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/vhdiinfo"; options = [ "NOPASSWD" ]; }
          ];
        }
      ];
    };

    # Create mount directory and helper scripts directory
    systemd.tmpfiles.rules = [
      "d ${cfg.mountsDir} 0750 ${xoUser} ${xoGroup} - -"
      "d /etc/xo 0755 root root - -"
      "d /etc/xo/bin 0755 root root - -"
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
    
    # Install helper scripts
    environment.etc = {
      "xo/mount-helper.sh" = {
        source = mountWrapper;
        mode = "0755";
      };
      "xo/umount-helper.sh" = {
        source = umountWrapper;
        mode = "0755";
      };
      "xo/bin/mount" = {
        source = mountCommandWrapper;
        mode = "0755";
      };
    } // lib.optionalAttrs cfg.vhd.enable {
      "xo/vhd-mount-helper.sh" = {
        source = vhdMountWrapper;
        mode = "0755";
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
