# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra Application - NixOS service module
# Provides declarative configuration, Redis backend, and systemd service
{ config, lib, pkgs, nixoaPackages, nixoaUtils, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.nixoa.xo;

  # Reference the configured package (will use user override if set, otherwise defaults)
  # Note: We use nixoaPackages.xen-orchestra-ce directly here since config values aren't fully
  # resolved in the let block. User overrides via xoa.package are handled in the options.
  xoaPackage = nixoaPackages.xen-orchestra-ce;

  # TOML format for rendering config from attrset
  tomlFormat = pkgs.formats.toml { };

  # XO app directory is now immutable in /nix/store
  xoAppDir = "${xoaPackage}/libexec/xen-orchestra";

  # Default home directory for XO service (can be overridden via cfg.home option)
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
    export HOME="${cfg.home}"
    export NODE_ENV="production"
    # Run the compiled xo-server entry point from the dist directory
    # The xo-server package is compiled to dist/cli.mjs as the entry point
    exec ${pkgs.nodejs_24}/bin/node "${xoAppDir}/packages/xo-server/dist/cli.mjs" "$@"
  '';

in
{
  options.nixoa.xo = {
    enable = mkEnableOption "Xen Orchestra from source";

    package = mkOption {
      type = types.package;
      default = nixoaPackages.xen-orchestra-ce;
      defaultText = lib.literalExpression "nixoaPackages.xen-orchestra-ce";
      description = ''
        The Xen Orchestra package to run.

        To enable the optional yarn chmod sanitizer build workaround:

          nixoa.xo.package = nixoaPackages.xen-orchestra-ce.override { enableChmodSanitizer = true; };

        (Keep it off unless you hit EPERM chmod failures during build.)
      '';
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to an xo-server config.toml file to be linked into /etc/xo-server/config.toml. Use this for secrets via agenix/sops.";
    };

    configNixoaFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a config.nixoa.toml file for NixOS-specific XO configuration overrides. Linked into /etc/xo-server/config.nixoa.toml.";
    };

    settings = mkOption {
      type = types.attrsOf types.unspecified;
      default = { };
      description = "xo-server configuration as a Nix attrset (rendered to TOML). Avoid putting secrets here; use configFile instead.";
    };

    # Service account (user and group are defined in users.nix under nixoa.xo.service)
    # Reference them directly from config.nixoa.xo.service

    http = {
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
    };

    tls = {
      enable = mkEnableOption "HTTPS with self-signed certificates";

      redirectToHttps = mkOption {
        type = types.bool;
        default = true;
        description = "Redirect HTTP traffic to HTTPS";
      };

      autoGenerate = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically generate self-signed certificates";
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

  config = mkIf cfg.enable (let
    # Get XO service user/group (defined in users.nix)
    xoUser = config.nixoa.xo.service.user;
    xoGroup = config.nixoa.xo.service.group;

    # Determine effective config source (priority: configFile > settings > sample.config.toml)
    effectiveConfigSource =
      if cfg.configFile != null then cfg.configFile
      else if cfg.settings != { } then tomlFormat.generate "xo-server-config.toml" cfg.settings
      else "${xoaPackage}/libexec/xen-orchestra/packages/xo-server/sample.config.toml";
  in {
    assertions = [
      {
        assertion = cfg.home != null;
        message = "XO home directory must be configured";
      }
    ];

    # Redis service for XO
    services.redis.servers.xo = {
      enable = true;
      user = xoUser;
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
      rsync openssl
      fuse fuse3 lvm2
      libguestfs    # VM disk inspection and mounting
      ntfs3g        # NTFS filesystem support for VM backups
    ];

    # Declarative config.toml linking
    # Priority: configFile > settings > sample.config.toml
    environment.etc."xo-server/config.toml" = {
      source = effectiveConfigSource;
      mode = "0640";
      user = "root";
      group = xoGroup;
    };

    # Declarative config.nixoa.toml linking (NixOS-specific overrides)
    environment.etc."xo-server/config.nixoa.toml" = mkIf (cfg.configNixoaFile != null) {
      source = cfg.configNixoaFile;
      mode = "0644";
      user = "root";
      group = xoGroup;
    };

    # XO Server service
    systemd.services.xo-server = {
      description = "Xen Orchestra Server";
      after = [
        "systemd-tmpfiles-setup.service"
        "network-online.target"
        "redis-xo.service"
      ] ++ lib.optional (config.nixoa.autocert.enable && cfg.tls.enable) "xo-autocert.service";

      wants = [ "network-online.target" "redis-xo.service" ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "redis-xo.service" ];
      
      # Sudo wrapper must be first in path to intercept sudo calls and handle env vars
      path = [ sudoWrapper ] ++ (with pkgs; [
        nodejs_24
        util-linux git openssl lvm2 coreutils
        nfs-utils cifs-utils  # For NFS and SMB remote storage handlers
      ]);
      
      # Environment for xo-server
      environment = cfg.extraServerEnv // {
        HOME = cfg.home;
        XDG_CONFIG_HOME = "${cfg.home}/.config";
        XDG_CACHE_HOME = cfg.cacheDir;
        NODE_ENV = "production";
        # Provide library paths for native modules (fuse-native, etc.)
        LD_LIBRARY_PATH = lib.makeLibraryPath [
          pkgs.fuse3
          pkgs.fuse
          pkgs.libguestfs
          pkgs.stdenv.cc.cc.lib
        ];
      };

      serviceConfig = {
        User = xoUser;
        Group = xoGroup;

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
        ReadOnlyPaths = lib.optionals cfg.tls.enable [ cfg.tls.dir ];

        ReadWritePaths = [
          cfg.home
          cfg.cacheDir
          cfg.dataDir
          cfg.tempDir
          "/etc/xo-server"
          "/var/lib/xo-server"  # XO server internal state directory
          config.nixoa.storage.mountsDir
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
      "d ${cfg.home}                          0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.cacheDir}                      0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.dataDir}                       0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.tempDir}                       0750 ${xoUser} ${xoGroup} - -"
      "d ${config.nixoa.storage.mountsDir}         0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.home}/.config                  0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.home}/.config/xo-server        0750 ${xoUser} ${xoGroup} - -"
      "d /etc/xo-server                          0755 root root - -"
      "d /var/lib/xo-server                      0750 ${xoUser} ${xoGroup} - -"
    ] ++ lib.optionals cfg.tls.enable [
      "d ${cfg.tls.dir}                       0755 root root - -"
    ];
  });
}
