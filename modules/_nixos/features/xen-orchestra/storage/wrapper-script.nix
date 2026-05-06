# SPDX-License-Identifier: Apache-2.0
# XO storage sudo wrapper script
{
  config,
  lib,
  pkgs,
  context,
  ...
}:
let
  inherit (lib) mkIf;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;

  sudoWrapper = pkgs.runCommand "xo-sudo-wrapper" { } ''
        mkdir -p $out/bin
        cat > $out/bin/sudo << 'EOF'
    #!/${pkgs.bash}/bin/bash
    set -euo pipefail

    storage_helper="${config.nixoa.xo.internal.storageHelper}/bin/xo-storage-helper"

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
        exec /run/wrappers/bin/sudo "''${sudo_opts[@]}" "$storage_helper" mount -o "$opts" "''${args[@]}"
      else
        exec /run/wrappers/bin/sudo "''${sudo_opts[@]}" "$storage_helper" mount "''${args[@]}"
      fi
    fi

    exec /run/wrappers/bin/sudo "''${sudo_opts[@]}" "$storage_helper" "$@"
    EOF
        chmod +x $out/bin/sudo
  '';
in
{
  config = mkIf storageEnabled {
    nixoa.xo.internal.sudoWrapper = sudoWrapper;
  };
}
