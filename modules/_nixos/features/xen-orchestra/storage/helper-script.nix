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

        fail() {
          echo "xo-storage-helper: $*" >&2
          exit 1
        }

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
          [ -n "$path" ] || fail "missing mount target"
          is_under "$mounts_dir" "$path" || fail "mount target must be under $mounts_dir: $path"
        }

        validate_runtime_path() {
          local path="''${1:-}"
          [ -n "$path" ] || fail "missing path"
          is_under "$mounts_dir" "$path" || is_under "$data_dir" "$path" || is_under "$temp_dir" "$path" \
            || fail "path must be under $mounts_dir, $data_dir, or $temp_dir: $path"
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

          if { [ "$fstype" = "nfs" ] || [ "$fstype" = "nfs4" ]; } && [ -z "$opts" ]; then
            opts="rw,soft,timeo=600,retrans=2"
          fi

          if [ -n "$opts" ]; then
            exec mount -o "$opts" "''${args[@]}"
          else
            exec mount "''${args[@]}"
          fi
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
