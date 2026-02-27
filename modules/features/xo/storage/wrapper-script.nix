# SPDX-License-Identifier: Apache-2.0
# XO storage sudo wrapper script
{
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;

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
  config = mkIf storageEnabled {
    nixoa.xo.internal.sudoWrapper = sudoWrapper;
  };
}
