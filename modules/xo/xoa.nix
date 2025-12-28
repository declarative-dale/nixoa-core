# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Application - NixOS service module
# Provides declarative configuration, Redis backend, and systemd service
{ config, lib, pkgs, nixoaPackages, nixoaUtils, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.xoa;

  # Reference the configured package (will use user override if set, otherwise defaults)
  # Note: We use nixoaPackages.xo-ce directly here since config values aren't fully
  # resolved in the let block. User overrides via xoa.package are handled in the options.
  xoaPackage = nixoaPackages.xo-ce;

  # TOML format for rendering config from attrset
  tomlFormat = pkgs.formats.toml { };

  # XO app directory is now immutable in /nix/store
  xoAppDir = "${xoaPackage}/libexec/xen-orchestra";

  # Default home directory for XO service (can be overridden via cfg.xo.home option)
  xoHome = "/var/lib/xo";

  # Sudo wrapper for CIFS mounts - injects credentials as mount options
  # This is the "Nix way" - transform the command instead of fighting sudo's env handling
  sudoWrapper = pkgs.runCommand "xo-sudo-wrapper" {} ''
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
    # Get the xo user's uid/gid for proper ownership
    XO_UID=$(id -u xo 2>/dev/null || echo "993")
    XO_GID=$(id -g xo 2>/dev/null || echo "990")

    # Trim leading/trailing whitespace from credentials (XOA may pass them with spaces)
    CLEAN_USER=$(echo "''${USER}" | xargs)
    CLEAN_PASSWD=$(echo "''${PASSWD}" | xargs)

    # Append credentials and ownership to existing options (no spaces!)
    if [ -n "$opts" ]; then
      opts="$opts,username=$CLEAN_USER,password=$CLEAN_PASSWD,uid=$XO_UID,gid=$XO_GID"
    else
      opts="username=$CLEAN_USER,password=$CLEAN_PASSWD,uid=$XO_UID,gid=$XO_GID"
    fi
  fi

  # Handle NFS mounts - ensure proper options
  if [ "$fstype" = "nfs" ] || [ "$fstype" = "nfs4" ]; then
    # Add default NFS options if none provided or empty string
    # Auto-negotiates version (tries v4, falls back to v3)
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

# Non-mount commands (findmnt, etc.) pass straight through
exec /run/wrappers/bin/sudo "$@"
EOF
    chmod +x $out/bin/sudo
  '';

  # Start script for xo-server (use compiled entry point)
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${cfg.xo.home}"
    export NODE_ENV="production"
    # Run the compiled xo-server entry point from the dist directory
    # The xo-server package is compiled to dist/cli.mjs as the entry point
    exec ${pkgs.nodejs_24}/bin/node "${xoAppDir}/packages/xo-server/dist/cli.mjs" "$@"
  '';

in
{
  options.xoa = {
    enable = mkEnableOption "Xen Orchestra from source";

    package = mkOption {
      type = types.package;
      default = nixoaPackages.xo-ce;
      defaultText = lib.literalExpression "nixoaPackages.xo-ce";
      description = ''
        The Xen Orchestra package to run.

        To enable the optional yarn chmod sanitizer build workaround:

          xoa.package = nixoaPackages.xo-ce.override { enableChmodSanitizer = true; };

        (Keep it off unless you hit EPERM chmod failures during build.)
      '';
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to an xo-server config.toml file to be linked into /etc/xo-server/config.toml. Use this for secrets via agenix/sops.";
    };

    settings = mkOption {
      type = types.attrsOf types.unspecified;
      default = { };
      description = "xo-server configuration as a Nix attrset (rendered to TOML). Avoid putting secrets here; use configFile instead.";
    };

    admin = {
      user = mkOption {
        type = types.str;
        default = "xoa";
        description = "Admin username for SSH access";
      };
      
      sshAuthorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "SSH public keys for admin user";
      };
    };

    xo = {
      user = mkOption {
        type = types.str;
        default = "xo";
        description = "System user for XO services";
      };
      
      group = mkOption {
        type = types.str;
        default = "xo";
        description = "System group for XO services";
      };
      
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Bind address for XO server";
      };
      
      port = mkOption {
        type = types.port;
        default = 80;
        description = "HTTP port";
      };
      
      httpsPort = mkOption {
        type = types.port;
        default = 443;
        description = "HTTPS port";
      };
      
      ssl = {
        enable = mkEnableOption "HTTPS with self-signed certificates";

        redirectToHttps = mkOption {
          type = types.bool;
          default = true;
          description = "Redirect HTTP traffic to HTTPS";
        };

        dir = mkOption {
          type = types.path;
          default = "/etc/ssl/xo";
          description = "Directory for SSL certificates";
        };

        cert = mkOption {
          type = types.path;
          default = "/etc/ssl/xo/certificate.pem";
          description = "SSL certificate path";
        };

        key = mkOption {
          type = types.path;
          default = "/etc/ssl/xo/key.pem";
          description = "SSL private key path";
        };
      };
      
      # Directory paths
      home = mkOption {
        type = types.path;
        default = xoHome;
        description = "XO service home directory";
      };

      cacheDir = mkOption {
        type = types.path;
        default = "${xoHome}/.cache";
        description = "Cache directory for builds";
      };
      
      dataDir = mkOption {
        type = types.path;
        default = "${xoHome}/data";
        description = "Data directory for XO";
      };
      
      tempDir = mkOption {
        type = types.path;
        default = "${xoHome}/tmp";
        description = "Temporary directory for XO operations";
      };

      extraServerEnv = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for xo-server";
      };
    };
  };

  config = mkIf cfg.enable (let
    # Determine effective config source (priority: configFile > settings > sample.config.toml)
    effectiveConfigSource =
      if cfg.configFile != null then cfg.configFile
      else if cfg.settings != { } then tomlFormat.generate "xo-server-config.toml" cfg.settings
      else "${xoaPackage}/libexec/xen-orchestra/packages/xo-server/sample.config.toml";
  in {
    assertions = [
      {
        assertion = cfg.admin.sshAuthorizedKeys != [];
        message = "You must provide at least one SSH public key in xoa.admin.sshAuthorizedKeys";
      }
    ];

    # Redis service for XO
    services.redis.servers.xo = {
      enable = true;
      user = cfg.xo.user;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings = { 
        port = 0; 
        databases = 16;
        maxmemory = "256mb";
        maxmemory-policy = "allkeys-lru";
      };
    };

    # System packages needed by XO (runtime only; build-time deps are in package derivation, not here)
    environment.systemPackages = with pkgs; [
      rsync micro openssl
      fuse fuse3 xen lvm2
      libguestfs    # VM disk inspection and mounting
      ntfs3g        # NTFS filesystem support for VM backups
    ];

    # Declarative config.toml linking
    # Priority: configFile > settings > sample.config.toml
    environment.etc."xo-server/config.toml" = {
      source = effectiveConfigSource;
      mode = "0640";
      user = "root";
      group = cfg.xo.group;
    };

    # XO Server service
    systemd.services.xo-server = {
      description = "Xen Orchestra Server";
      after = [
        "systemd-tmpfiles-setup.service"
        "network-online.target"
        "redis-xo.service"
      ] ++ lib.optional (config.xoa.autocert.enable && cfg.xo.ssl.enable) "xo-autocert.service";

      wants = [ "network-online.target" "redis-xo.service" ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "redis-xo.service" ];
      
      # Sudo wrapper must be first in path to intercept sudo calls and handle env vars
      path = [ sudoWrapper ] ++ (with pkgs; [
        nodejs_24
        util-linux git openssl xen lvm2 coreutils
        nfs-utils cifs-utils  # For NFS and SMB remote storage handlers
      ]);
      
      # Environment for xo-server
      environment = cfg.xo.extraServerEnv // {
        HOME = cfg.xo.home;
        XDG_CONFIG_HOME = "${cfg.xo.home}/.config";
        XDG_CACHE_HOME = cfg.xo.cacheDir;
        NODE_ENV = "production";
      };

      serviceConfig = {
        User = cfg.xo.user;
        Group = cfg.xo.group;

        WorkingDirectory = xoAppDir;
        StateDirectory = "xo";
        CacheDirectory = "xo";
        LogsDirectory = "xo";
        RuntimeDirectory = "xo xo-server";

        # PATH is automatically built from the 'path' directive above
        # Don't override it here to ensure our sudo wrapper is found first

        # XO automatically loads all config files from /etc/xo-server/:
        # - config.toml (XO's built-in defaults, created by XO on first run)
        # - config.nixoa.toml (nixoa overrides, placed by user-config via environment.etc)
        ExecStart = "${startXO}";
        
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5min";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "full";  # Makes /usr, /boot, /efi read-only (strict is too restrictive)
        ProtectHome = true;
        PrivateDevices = false;  # Need device access for LVM and xenstore

        # Capabilities for HTTP/HTTPS ports and sudo operations
        # Note: system.nix overrides these with mkForce, but we set sensible defaults
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" "CAP_SETUID" "CAP_SETGID" "CAP_SETPCAP" "CAP_SYS_ADMIN" "CAP_DAC_OVERRIDE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" "CAP_SETUID" "CAP_SETGID" "CAP_SETPCAP" "CAP_SYS_ADMIN" "CAP_DAC_OVERRIDE" ];

        # Allow reading SSL certs (libraries accessible via ProtectSystem=full)
        ReadOnlyPaths = lib.optionals cfg.xo.ssl.enable [ cfg.xo.ssl.dir ];

        ReadWritePaths = [
          cfg.xo.home
          cfg.xo.cacheDir
          cfg.xo.dataDir
          cfg.xo.tempDir
          "/etc/xo-server"
          "/var/lib/xo-server"  # XO server internal state directory
          config.xoa.storage.mountsDir
          "/run/lock"           # LVM lock files
          "/run/redis-xo"       # Redis socket
          "/dev"                # Device access for LVM/storage operations
          "/sys"                # Sysfs access for xenstore
          "/var/log"            # Sudo audit logs
        ];
        
        LimitNOFILE = "1048576";
      };
    };
    
    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d ${cfg.xo.home}                          0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.cacheDir}                      0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.dataDir}                       0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.tempDir}                       0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${config.xoa.storage.mountsDir}         0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.home}/.config                  0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.home}/.config/xo-server        0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d /etc/xo-server                          0755 root root - -"
      "d /var/lib/xo-server                      0750 ${cfg.xo.user} ${cfg.xo.group} - -"
    ] ++ lib.optionals cfg.xo.ssl.enable [
      "d ${cfg.xo.ssl.dir}                       0755 root root - -"
    ];
  });
}
