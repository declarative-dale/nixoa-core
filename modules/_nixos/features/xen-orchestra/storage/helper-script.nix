# SPDX-License-Identifier: Apache-2.0
# XO root storage helper with command and path validation
{
  config,
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) concatMapStringsSep concatStringsSep mkIf optional optionals;
  cfg = config.nixoa.xo;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;
  allowedMountTypes =
    optional context.enableCIFS "cifs"
    ++ optionals context.enableNFS [
      "nfs"
      "nfs4"
    ];
  allowedMountTypeCases = concatMapStringsSep "\n" (fstype: "        ${fstype}) ;;") allowedMountTypes;
  allowedMountTypeList = concatStringsSep ", " allowedMountTypes;
  helperPath = lib.makeBinPath (
    [
      pkgs.coreutils
      pkgs.util-linux
    ]
    ++ optionals context.enableNFS [pkgs.nfs-utils]
    ++ optionals context.enableCIFS [pkgs.cifs-utils]
    ++ lib.optionals context.enableVHD [config.services.libvhdi.package]
  );
  storageHelper = pkgs.writeShellScriptBin "xo-storage-helper" ''
        set -euo pipefail

        export PATH=${lib.escapeShellArg helperPath}:$PATH

        mounts_dir=${lib.escapeShellArg context.mountsDir}
        data_dir=${lib.escapeShellArg cfg.dataDir}
        temp_dir=${lib.escapeShellArg cfg.tempDir}
        cifs_credentials_dir="/run/xo-server/cifs-credentials"
        xo_user=${lib.escapeShellArg cfg.user}

        fail() {
          echo "xo-storage-helper: $*" >&2
          exit 1
        }

        canonical_path() {
          local path="''${1:-}"
          [ -n "$path" ] || fail "missing path"
          case "$path" in
            /*) ;;
            *) fail "path must be absolute: $path" ;;
          esac
          realpath -m -- "$path"
        }

        mounts_dir="$(canonical_path "$mounts_dir")"
        data_dir="$(canonical_path "$data_dir")"
        temp_dir="$(canonical_path "$temp_dir")"

        is_under() {
          local root="$1"
          local path="$2"
          case "$path" in
            "$root"|"$root"/*) return 0 ;;
            *) return 1 ;;
          esac
        }

        validate_mount_target() {
          local path="''${1:-}"
          local canonical
          canonical="$(canonical_path "$path")"
          is_under "$mounts_dir" "$canonical" || fail "mount target must be under $mounts_dir: $path"
        }

        validate_runtime_path() {
          local path="''${1:-}"
          local canonical
          canonical="$(canonical_path "$path")"
          is_under "$mounts_dir" "$canonical" || is_under "$data_dir" "$canonical" || is_under "$temp_dir" "$canonical" \
            || fail "path must be under $mounts_dir, $data_dir, or $temp_dir: $path"
        }

        reject_cifs_secret_options() {
          local opts="''${1:-}"
          local old_ifs="$IFS"
          local opt key
          IFS=,
          for opt in $opts; do
            key="''${opt%%=*}"
            key="''${key,,}"
            case "$key" in
              user|username|pass|password|password2|cred|credentials)
                fail "CIFS credential option is not allowed in mount options: $key"
                ;;
            esac
          done
          IFS="$old_ifs"
        }

        run_mount() {
          local fstype=""
          local opts=""
          local args=()
          local positional=()

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
                opts="$2"
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
          local target="''${positional[$((''${#positional[@]} - 1))]}"
          validate_mount_target "$target"

          case "$fstype" in
    ${allowedMountTypeCases}
            *) fail "mount filesystem type is not allowed: ''${fstype:-<unset>} (allowed: ${allowedMountTypeList})" ;;
          esac

          if [ "$fstype" = "cifs" ]; then
            reject_cifs_secret_options "$opts"
          fi

          if { [ "$fstype" = "nfs" ] || [ "$fstype" = "nfs4" ]; } && [ -z "$opts" ]; then
            opts="rw,soft,timeo=600,retrans=2"
          fi

          if [ -n "$opts" ]; then
            exec mount -o "$opts" "''${args[@]}"
          else
            exec mount "''${args[@]}"
          fi
        }

        run_mount_cifs_with_credentials() {
          local fstype=""
          local opts=""
          local args=()
          local positional=()

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
                opts="$2"
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

          [ "$fstype" = "cifs" ] || fail "internal CIFS mount requires -t cifs"
          [ "''${#positional[@]}" -ge 2 ] || fail "mount requires source and target"
          local target="''${positional[$((''${#positional[@]} - 1))]}"
          validate_mount_target "$target"
          reject_cifs_secret_options "$opts"

          local cifs_user=""
          local cifs_password=""
          IFS= read -r cifs_user || fail "missing CIFS username on stdin"
          IFS= read -r cifs_password || fail "missing CIFS password on stdin"
          [ -n "$cifs_user" ] || fail "missing CIFS username"

          mkdir -p "$cifs_credentials_dir"
          chown root:root "$cifs_credentials_dir"
          chmod 0700 "$cifs_credentials_dir"

          local credentials_file
          credentials_file="$(mktemp "$cifs_credentials_dir/credentials.XXXXXX")"
          CIFS_CREDENTIALS_FILE="$credentials_file"
          trap 'rm -f -- "''${CIFS_CREDENTIALS_FILE:-}"' EXIT
          chmod 0600 "$credentials_file"
          {
            printf 'username=%s\n' "$cifs_user"
            printf 'password=%s\n' "$cifs_password"
          } > "$credentials_file"

          local xo_uid xo_gid
          xo_uid="$(id -u "$xo_user")"
          xo_gid="$(id -g "$xo_user")"

          local credential_opts="credentials=$credentials_file,uid=$xo_uid,gid=$xo_gid"
          if [ -n "$opts" ]; then
            opts="$opts,$credential_opts"
          else
            opts="$credential_opts"
          fi

          mount -o "$opts" "''${args[@]}"
        }

        run_umount() {
          local args=()
          local saw_target=0

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -t|--types)
                [ "$#" -ge 2 ] || fail "$1 requires an argument"
                args+=("$1" "$2")
                shift 2
                ;;
              -*)
                args+=("$1")
                shift
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

          [ "$saw_target" -eq 1 ] || fail "umount requires a target under $mounts_dir"
          exec umount "''${args[@]}"
        }

        run_findmnt() {
          local args=()
          local saw_target=0

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -T|--target|-M|--mountpoint)
                [ "$#" -ge 2 ] || fail "$1 requires an argument"
                validate_mount_target "$2"
                saw_target=1
                args+=("$1" "$2")
                shift 2
                ;;
              -*)
                args+=("$1")
                shift
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

          [ "$saw_target" -eq 1 ] || fail "findmnt requires a target under $mounts_dir"
          exec findmnt "''${args[@]}"
        }

        run_vhdimount() {
          local args=()
          local positional=()

          while [ "$#" -gt 0 ]; do
            case "$1" in
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

          [ "''${#positional[@]}" -ge 2 ] || fail "vhdimount requires image and target"
          local image="''${positional[$((''${#positional[@]} - 2))]}"
          local target="''${positional[$((''${#positional[@]} - 1))]}"
          validate_runtime_path "$image"
          validate_mount_target "$target"
          exec vhdimount "''${args[@]}"
        }

        run_vhdiinfo() {
          local args=()
          local saw_path=0

          while [ "$#" -gt 0 ]; do
            case "$1" in
              -*)
                args+=("$1")
                shift
                ;;
              /*)
                validate_runtime_path "$1"
                saw_path=1
                args+=("$1")
                shift
                ;;
              *)
                args+=("$1")
                shift
                ;;
            esac
          done

          [ "$saw_path" -eq 1 ] || fail "vhdiinfo requires an image path under XO runtime storage"
          exec vhdiinfo "''${args[@]}"
        }

        [ "$#" -ge 1 ] || fail "missing command"
        command="$1"
        shift

        case "$command" in
          mount) run_mount "$@" ;;
          mount-cifs-with-credentials)
            ${lib.optionalString (!context.enableCIFS) ''fail "CIFS mounting is disabled"''}
            run_mount_cifs_with_credentials "$@"
            ;;
          umount) run_umount "$@" ;;
          findmnt) run_findmnt "$@" ;;
          vhdimount)
            ${lib.optionalString (!context.enableVHD) ''fail "vhdimount is disabled"''}
            run_vhdimount "$@"
            ;;
          vhdiinfo)
            ${lib.optionalString (!context.enableVHD) ''fail "vhdiinfo is disabled"''}
            run_vhdiinfo "$@"
            ;;
          *) fail "command is not allowed: $command" ;;
        esac
  '';
in {
  config = mkIf storageEnabled {
    nixoa.xo.internal.storageHelper = storageHelper;
  };
}
