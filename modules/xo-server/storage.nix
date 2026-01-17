# SPDX-License-Identifier: Apache-2.0
# XO Server storage - NFS/CIFS/VHD mounts, sudo wrapper, libvhdi
{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf;

  xoUser = vars.xoUser;
  xoGroup = vars.xoGroup;
  cfg = config.services.libvhdi;

  # Sudo wrapper for CIFS mounts - injects credentials as mount options
  sudoWrapper = pkgs.runCommand "xo-sudo-wrapper" { } ''
        mkdir -p $out/bin
        cat > $out/bin/sudo << 'EOF'
    #!/${pkgs.bash}/bin/bash
    set -euo pipefail

    # Special case: sudo mount ... -t cifs ...
    # Everything else passes through to real sudo unchanged
    if [ "$#" -ge 1 ] && [ "$1" = "mount" ]; then
      shift

      fstype=""
      opts=""
      args=()

      # Parse mount arguments to extract -t and -o
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -t)
            fstype="$2"
            args+=("-t" "$2")
            shift 2
            ;;
          -o)
            opts="$2"
            shift 2
            ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done

      # Handle CIFS mounts - inject credentials and ownership
      if [ "$fstype" = "cifs" ] && [ -n "''${USER:-}" ] && [ -n "''${PASSWD:-}" ]; then
        XO_UID=$(id -u xo 2>/dev/null || echo "993")
        XO_GID=$(id -g xo 2>/dev/null || echo "990")

        CLEAN_USER=$(echo "''${USER}" | xargs)
        CLEAN_PASSWD=$(echo "''${PASSWD}" | xargs)

        if [ -n "$opts" ]; then
          opts="$opts,username=$CLEAN_USER,password=$CLEAN_PASSWD,uid=$XO_UID,gid=$XO_GID"
        else
          opts="username=$CLEAN_USER,password=$CLEAN_PASSWD,uid=$XO_UID,gid=$XO_GID"
        fi
      fi

      # Handle NFS mounts - ensure proper options
      if [ "$fstype" = "nfs" ] || [ "$fstype" = "nfs4" ]; then
        if [ -z "$opts" ]; then
          opts="rw,soft,timeo=600,retrans=2"
        fi
      fi

      # Reassemble and call real sudo + mount
      if [ -n "$opts" ]; then
        exec /run/wrappers/bin/sudo /run/current-system/sw/bin/mount -o "$opts" "''${args[@]}"
      else
        exec /run/wrappers/bin/sudo /run/current-system/sw/bin/mount "''${args[@]}"
      fi
    fi

    # Non-mount commands pass straight through
    exec /run/wrappers/bin/sudo "$@"
    EOF
        chmod +x $out/bin/sudo
  '';
in
{
  config = mkIf (vars.enableNFS || vars.enableCIFS || vars.enableVHD) {
    # Expose sudo wrapper to service.nix
    nixoa.xo.internal.sudoWrapper = sudoWrapper;

    # Setuid wrapper for mount.cifs
    security.wrappers = lib.mkIf vars.enableCIFS {
      "mount.cifs" = {
        program = "mount.cifs";
        source = "${lib.getBin pkgs.cifs-utils}/bin/mount.cifs";
        owner = "root";
        group = "root";
        setuid = true;
      };
    };

    # Sudo configuration
    security.sudo.extraConfig = ''
      Defaults !use_pty
      Defaults !log_subcmds
      Defaults:${xoUser} !use_pty,!syslog
    '';

    # Filesystem tools
    environment.systemPackages =
      lib.optionals vars.enableNFS [ pkgs.nfs-utils ]
      ++ lib.optionals vars.enableCIFS [ pkgs.cifs-utils ]
      ++ lib.optionals vars.enableVHD [ cfg.package ];

    # Enable libvhdi if VHD support requested
    services.libvhdi.enable = vars.enableVHD;

    # FUSE support
    programs.fuse.userAllowOther = true;
    boot.kernelModules =
      [ "fuse" ]
      ++ lib.optionals vars.enableNFS [
        "nfs"
        "nfsv4"
      ]
      ++ lib.optionals vars.enableCIFS [ "cifs" ];

    boot.supportedFilesystems =
      lib.optionals vars.enableNFS [
        "nfs"
        "nfs4"
      ]
      ++ lib.optionals vars.enableCIFS [ "cifs" ];

    # Sudo rules for mount operations
    security.sudo = {
      enable = true;
      extraRules = [
        {
          users = [ xoUser ];
          commands =
            [
              {
                command = "/run/current-system/sw/bin/mount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/umount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/findmnt";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/wrappers/bin/mount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/wrappers/bin/umount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/wrappers/bin/findmnt";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/nix/store/*/bin/mount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/nix/store/*/bin/umount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/nix/store/*/bin/findmnt";
                options = [ "NOPASSWD" ];
              }
            ]
            ++ lib.optionals vars.enableVHD [
              {
                command = "/run/current-system/sw/bin/vhdimount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/vhdiinfo";
                options = [ "NOPASSWD" ];
              }
            ];
        }
      ];
    };

    # Mount directory
    systemd.tmpfiles.rules = [
      "d ${vars.mountsDir} 0750 ${xoUser} ${xoGroup} - -"
    ];

    # Initialize sudo for xo user
    systemd.services.xo-sudo-init = {
      description = "Initialize sudo for XO user";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "xo-sudo-init" ''
          if [ ! -f /var/db/sudo/lectured/${xoUser} ]; then
            mkdir -p /var/db/sudo/lectured
            touch /var/db/sudo/lectured/${xoUser}
            chown root:root /var/db/sudo/lectured/${xoUser}
            chmod 0600 /var/db/sudo/lectured/${xoUser}
          fi
        ''}";
      };
    };

    assertions = [
      {
        assertion =
          config.users.users.${xoUser}.extraGroups or [ ] != [ ]
          -> builtins.elem "fuse" config.users.users.${xoUser}.extraGroups;
        message = "XO user must be in 'fuse' group for remote storage mounting";
      }
      {
        assertion = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
        message = "At least one storage type must be enabled (NFS, CIFS, or VHD)";
      }
    ];
  };
}
