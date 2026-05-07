# SPDX-License-Identifier: Apache-2.0
# XO storage sudo wrapper script
{
  config,
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) mkIf optional;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;

  sudoCommand = pkgs.writeShellScriptBin "sudo" ''
    set -euo pipefail

    storage_helper="${config.nixoa.xo.internal.storageHelper}/bin/xo-storage-helper"

    trim() {
      local value="$1"
      value="''${value#"''${value%%[![:space:]]*}"}"
      value="''${value%"''${value##*[![:space:]]}"}"
      printf '%s' "$value"
    }

    sudo_opts=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -n|-E|-H)
          sudo_opts+=("$1")
          shift
          ;;
        --)
          shift
          break
          ;;
        -*)
          break
          ;;
        *)
          break
          ;;
      esac
    done

    # Special case: sudo mount ... -t cifs ...
    # CIFS credentials are provided by XO in the service environment, so inject
    # them before sudo resets the environment and then call the root helper.
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
        XO_UID=$(${pkgs.coreutils}/bin/id -u xo 2>/dev/null || echo "993")
        XO_GID=$(${pkgs.coreutils}/bin/id -g xo 2>/dev/null || echo "990")

        CLEAN_USER=$(trim "''${USER}")
        CLEAN_PASSWD=$(trim "''${PASSWD}")

        if [ -n "$opts" ]; then
          opts="$opts,username=$CLEAN_USER,password=$CLEAN_PASSWD,uid=$XO_UID,gid=$XO_GID"
        else
          opts="username=$CLEAN_USER,password=$CLEAN_PASSWD,uid=$XO_UID,gid=$XO_GID"
        fi
      fi

      # Reassemble and call real sudo + mount
      if [ -n "$opts" ]; then
        exec /run/wrappers/bin/sudo "''${sudo_opts[@]}" "$storage_helper" mount -o "$opts" "''${args[@]}"
      else
        exec /run/wrappers/bin/sudo "''${sudo_opts[@]}" "$storage_helper" mount "''${args[@]}"
      fi
    fi

    exec /run/wrappers/bin/sudo "''${sudo_opts[@]}" "$storage_helper" "$@"
  '';

  cifsProbeShim = pkgs.writeShellScriptBin "mount.cifs" ''
    set -euo pipefail

    # XO uses `mount.cifs -V` as an SMB handler availability probe. The Nix
    # store binary exits non-zero for that probe as the unprivileged xo user
    # because it is not setuid root, even though CIFS mounts are performed
    # later through sudo and the validated root storage helper.
    if [ "$#" -eq 1 ] && { [ "$1" = "-V" ] || [ "$1" = "--version" ]; }; then
      echo "mount.cifs version ${pkgs.cifs-utils.version or "unknown"}"
      exit 0
    fi

    exec ${pkgs.cifs-utils}/bin/mount.cifs "$@"
  '';

  sudoWrapper = pkgs.symlinkJoin {
    name = "xo-storage-command-wrapper";
    paths = [sudoCommand] ++ optional context.enableCIFS cifsProbeShim;
  };
in {
  config = mkIf storageEnabled {
    nixoa.xo.internal.sudoWrapper = sudoWrapper;
  };
}
