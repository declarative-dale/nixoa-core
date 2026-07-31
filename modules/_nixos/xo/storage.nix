# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixoa.xo;
  storage = cfg.storage;
  enabled = cfg.enable && (storage.enableNFS || storage.enableCIFS || storage.enableVHD);
  allowedMountTypes =
    lib.optional storage.enableCIFS "cifs"
    ++ lib.optionals storage.enableNFS [
      "nfs"
      "nfs4"
    ];
  allowedMountCases = lib.concatMapStringsSep "\n" (fstype: "      ${fstype}) ;;") allowedMountTypes;
  helperPath = lib.makeBinPath (
    [
      pkgs.coreutils
      pkgs.util-linux
    ]
    ++ lib.optionals storage.enableNFS [pkgs.nfs-utils]
    ++ lib.optionals storage.enableCIFS [pkgs.cifs-utils]
    ++ lib.optionals storage.enableVHD [storage.libvhdiPackage]
  );
  storageHelper = pkgs.writeShellScriptBin "xo-storage-helper" ''
        set -euo pipefail
        export PATH=${lib.escapeShellArg helperPath}:$PATH

        mounts_dir="$(realpath -m -- ${lib.escapeShellArg storage.mountsDir})"
        data_dir="$(realpath -m -- ${lib.escapeShellArg cfg.dataDir})"
        temp_dir="$(realpath -m -- ${lib.escapeShellArg cfg.tempDir})"
        credentials_dir=/run/xo-server/cifs-credentials

        fail() {
          echo "xo-storage-helper: $*" >&2
          exit 1
        }

        canonical_path() {
          case "''${1:-}" in
            /*) realpath -m -- "$1" ;;
            *) fail "path must be absolute: ''${1:-<missing>}" ;;
          esac
        }

        is_under() {
          case "$2" in
            "$1"|"$1"/*) return 0 ;;
            *) return 1 ;;
          esac
        }

        validate_mount_target() {
          local path
          path="$(canonical_path "''${1:-}")"
          is_under "$mounts_dir" "$path" \
            || fail "mount target must be under $mounts_dir: $path"
        }

        validate_runtime_path() {
          local path
          path="$(canonical_path "''${1:-}")"
          is_under "$mounts_dir" "$path" \
            || is_under "$data_dir" "$path" \
            || is_under "$temp_dir" "$path" \
            || fail "path is outside XO runtime storage: $path"
        }

        reject_cifs_secrets() {
          local old_ifs="$IFS"
          local option key
          IFS=,
          for option in ''${1:-}; do
            key="''${option%%=*}"
            key="''${key,,}"
            case "$key" in
              user|username|pass|password|password2|cred|credentials)
                fail "CIFS credentials are not allowed in mount arguments"
                ;;
            esac
          done
          IFS="$old_ifs"
        }

        run_mount() {
          local fstype="" options=""
          local -a args=() positional=()

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -t|--types)
                [ "$#" -ge 2 ] || fail "$1 requires an argument"
                fstype="$2"
                args+=("$1" "$2")
                shift 2
                ;;
              -o|--options)
                [ "$#" -ge 2 ] || fail "$1 requires an argument"
                options="$2"
                shift 2
                ;;
              -*)
                args+=("$1")
                shift
                ;;
              *)
                positional+=("$1")
                args+=("$1")
                shift
                ;;
            esac
          done

          [ "''${#positional[@]}" -ge 2 ] || fail "mount requires source and target"
          validate_mount_target "''${positional[$((''${#positional[@]} - 1))]}"
          case "$fstype" in
    ${allowedMountCases}
            *) fail "filesystem type is not enabled: ''${fstype:-<unset>}" ;;
          esac
          [ "$fstype" != cifs ] || reject_cifs_secrets "$options"
          if { [ "$fstype" = nfs ] || [ "$fstype" = nfs4 ]; } && [ -z "$options" ]; then
            options=rw,soft,timeo=600,retrans=2
          fi
          if [ -n "$options" ]; then
            exec mount -o "$options" "''${args[@]}"
          fi
          exec mount "''${args[@]}"
        }

        run_cifs() {
          local options=""
          local -a args=() positional=()

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -t|--types)
                [ "$#" -ge 2 ] && [ "$2" = cifs ] || fail "CIFS mount requires -t cifs"
                args+=("$1" "$2")
                shift 2
                ;;
              -o|--options)
                [ "$#" -ge 2 ] || fail "$1 requires an argument"
                options="$2"
                shift 2
                ;;
              -*)
                args+=("$1")
                shift
                ;;
              *)
                positional+=("$1")
                args+=("$1")
                shift
                ;;
            esac
          done

          [ "''${#positional[@]}" -ge 2 ] || fail "mount requires source and target"
          validate_mount_target "''${positional[$((''${#positional[@]} - 1))]}"
          reject_cifs_secrets "$options"

          local username="" password="" credentials_file=""
          IFS= read -r username || fail "missing CIFS username"
          IFS= read -r password || fail "missing CIFS password"
          [ -n "$username" ] || fail "missing CIFS username"

          install -d -m 0700 -o root -g root "$credentials_dir"
          credentials_file="$(mktemp "$credentials_dir/credentials.XXXXXX")"
          trap 'rm -f -- "''${credentials_file:-}"' EXIT
          chmod 0600 "$credentials_file"
          printf 'username=%s\npassword=%s\n' "$username" "$password" > "$credentials_file"

          local credential_options
          credential_options="credentials=$credentials_file,uid=$(id -u ${lib.escapeShellArg cfg.user}),gid=$(id -g ${lib.escapeShellArg cfg.user})"
          if [ -n "$options" ]; then
            options="$options,$credential_options"
          else
            options="$credential_options"
          fi
          mount -o "$options" "''${args[@]}"
        }

        run_target_command() {
          local command="$1"
          shift
          local -a args=()
          local saw_target=0

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -T|--target|-M|--mountpoint|-t|--types)
                [ "$#" -ge 2 ] || fail "$1 requires an argument"
                case "$1" in
                  -T|--target|-M|--mountpoint)
                    validate_mount_target "$2"
                    saw_target=1
                    ;;
                esac
                args+=("$1" "$2")
                shift 2
                ;;
              /*)
                validate_mount_target "$1"
                saw_target=1
                args+=("$1")
                shift
                ;;
              *)
                args+=("$1")
                shift
                ;;
            esac
          done
          [ "$saw_target" -eq 1 ] || fail "$command requires a target under $mounts_dir"
          exec "$command" "''${args[@]}"
        }

        run_vhdi() {
          local command="$1"
          shift
          local -a args=() positional=()
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -*) args+=("$1"); shift ;;
              *) positional+=("$1"); args+=("$1"); shift ;;
            esac
          done
          if [ "$command" = vhdimount ]; then
            [ "''${#positional[@]}" -ge 2 ] || fail "vhdimount requires image and target"
            validate_runtime_path "''${positional[$((''${#positional[@]} - 2))]}"
            validate_mount_target "''${positional[$((''${#positional[@]} - 1))]}"
          else
            [ "''${#positional[@]}" -ge 1 ] || fail "vhdiinfo requires an image"
            validate_runtime_path "''${positional[$((''${#positional[@]} - 1))]}"
          fi
          exec "$command" "''${args[@]}"
        }

        [ "$#" -ge 1 ] || fail "missing command"
        command="$1"
        shift
        case "$command" in
          mount) run_mount "$@" ;;
          mount-cifs-with-credentials)
            ${lib.optionalString (!storage.enableCIFS) ''fail "CIFS support is disabled"''}
            run_cifs "$@"
            ;;
          umount|findmnt) run_target_command "$command" "$@" ;;
          vhdimount|vhdiinfo)
            ${lib.optionalString (!storage.enableVHD) ''fail "VHD support is disabled"''}
            run_vhdi "$command" "$@"
            ;;
          *) fail "command is not allowed: $command" ;;
        esac
  '';
  sudoCommand = pkgs.writeShellScriptBin "sudo" ''
    set -euo pipefail
    helper=${storageHelper}/bin/xo-storage-helper
    sudo_options=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -n|-E|-H) sudo_options+=("$1"); shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done

    if [ "''${1:-}" = mount ]; then
      shift
      fstype="" options=""
      args=()
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -t|--types)
            fstype="$2"
            args+=("$1" "$2")
            shift 2
            ;;
          -o|--options)
            options="$2"
            shift 2
            ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done
      if [ "$fstype" = cifs ] && [ -n "''${USER:-}" ] && [ -n "''${PASSWD:-}" ]; then
        if [ -n "$options" ]; then
          printf '%s\n%s\n' "$USER" "$PASSWD" \
            | /run/wrappers/bin/sudo "''${sudo_options[@]}" "$helper" mount-cifs-with-credentials -o "$options" "''${args[@]}"
        else
          printf '%s\n%s\n' "$USER" "$PASSWD" \
            | /run/wrappers/bin/sudo "''${sudo_options[@]}" "$helper" mount-cifs-with-credentials "''${args[@]}"
        fi
        exit $?
      fi
      if [ -n "$options" ]; then
        exec /run/wrappers/bin/sudo "''${sudo_options[@]}" "$helper" mount -o "$options" "''${args[@]}"
      fi
      exec /run/wrappers/bin/sudo "''${sudo_options[@]}" "$helper" mount "''${args[@]}"
    fi
    exec /run/wrappers/bin/sudo "''${sudo_options[@]}" "$helper" "$@"
  '';
  cifsProbe = pkgs.writeShellScriptBin "mount.cifs" ''
    if [ "$#" -eq 1 ] && { [ "$1" = -V ] || [ "$1" = --version ]; }; then
      echo "mount.cifs version ${pkgs.cifs-utils.version or "unknown"}"
      exit 0
    fi
    exec ${pkgs.cifs-utils}/bin/mount.cifs "$@"
  '';
  commandWrapper = pkgs.symlinkJoin {
    name = "xo-storage-command-wrapper";
    paths = [sudoCommand] ++ lib.optional storage.enableCIFS cifsProbe;
  };
in {
  config = lib.mkIf enabled {
    nixoa.xo.internal.sudoWrapper = commandWrapper;

    programs.fuse.userAllowOther = true;
    boot.kernelModules =
      ["fuse"]
      ++ lib.optionals storage.enableNFS [
        "nfs"
        "nfsv4"
      ]
      ++ lib.optional storage.enableCIFS "cifs";
    boot.supportedFilesystems =
      lib.optionals storage.enableNFS [
        "nfs"
        "nfs4"
      ]
      ++ lib.optional storage.enableCIFS "cifs";

    services.rpcbind.enable = storage.enableNFS;
    services.nfs.server.enable = false;

    environment.systemPackages = lib.optional storage.enableVHD storage.libvhdiPackage;
    systemd.tmpfiles.rules = [
      "d ${storage.mountsDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    security.sudo = {
      enable = true;
      extraConfig = ''
        Defaults:${cfg.user} !use_pty,!log_subcmds,!syslog
      '';
      extraRules = [
        {
          users = [cfg.user];
          commands = [
            {
              command = "${storageHelper}/bin/xo-storage-helper";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];
    };

    systemd.services.xo-sudo-init = {
      description = "Initialize sudo for the XO user";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "xo-sudo-init" ''
          install -d -m 0700 -o root -g root /var/db/sudo/lectured
          install -m 0600 -o root -g root /dev/null /var/db/sudo/lectured/${cfg.user}
        '';
      };
    };

    assertions = [
      {
        assertion = builtins.elem "fuse" config.users.users.${cfg.user}.extraGroups;
        message = "The XO service user must belong to the fuse group.";
      }
    ];
  };
}
