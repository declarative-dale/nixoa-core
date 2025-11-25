{ config, lib, pkgs, xoSrc ? null, vars, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.xoa;

  node   = pkgs.nodejs_20;
  yarn   = pkgs.yarn;
  rsync  = pkgs.rsync;
  openssl = pkgs.openssl;
  
  # Properly define xoSource - this was missing in the original!
  xoSource = if xoSrc != null then xoSrc else pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo = "xen-orchestra";
    rev = "master";
    hash = lib.fakeHash; # Replace with actual hash after first build attempt
  };
  
  # XO home directory
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
  
  # Fixed xo-server config with proper HTTPS setup
  xoDefaultConfig = pkgs.writeText "xo-config-default.toml" (''
    [http]
  '' + lib.optionalString (cfg.xo.ssl.enable && cfg.xo.ssl.redirectToHttps) ''
    redirectToHttps = true
  '' + ''

    [[http.listen]]
    port = ${toString cfg.xo.port}
  '' + lib.optionalString cfg.xo.ssl.enable ''

    [[http.listen]]
    port = ${toString cfg.xo.httpsPort}
    cert = '${cfg.xo.ssl.cert}'
    key = '${cfg.xo.ssl.key}'
  '' + ''

    [http.mounts]
    '/' = '${cfg.xo.webMountDir}'
  '' + lib.optionalString cfg.xo.enableV6Preview ''
    '/v6' = '${cfg.xo.webMountDirv6}'
  '' + ''

    [redis]
    socket = "/run/redis-xo/redis.sock"

    [authentication]
    defaultTokenValidity = "30 days"

    [logs]
    level = "info"

    # Data paths
    [dataStore]
    path = '${cfg.xo.dataDir}'

    [tempDir]
    path = '${cfg.xo.tempDir}'

    # Remote storage options - use sudo for NFS/CIFS mounts
    [remoteOptions]
    useSudo = true
    mountsDir = '${config.xoa.storage.mountsDir}'
  '');

  # Simple certificate generation script (only for SSL)
  genCerts = pkgs.writeShellScript "xo-gen-certs.sh" ''
    set -euo pipefail
    umask 077

    # Directory should already exist from tmpfiles, but ensure it does
    if [ ! -d "${cfg.xo.ssl.dir}" ]; then
      mkdir -p "${cfg.xo.ssl.dir}"
      chmod 0755 "${cfg.xo.ssl.dir}"
    fi

    # Generate certificates if they don't exist
    if [ ! -s "${cfg.xo.ssl.key}" ] || [ ! -s "${cfg.xo.ssl.cert}" ]; then
      ${openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
        -keyout "${cfg.xo.ssl.key}" -out "${cfg.xo.ssl.cert}" \
        -subj "/CN=${config.networking.hostName}" \
        -addext "subjectAltName=DNS:${config.networking.hostName},DNS:localhost,IP:${cfg.xo.host}"
      chown ${cfg.xo.user}:${cfg.xo.group} "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}"
      chmod 0640 "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}"
    fi
  '';

  # Build script with directory creation
  buildXO = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022

    # Create all required directories first
    install -d -m 0750 -o ${cfg.xo.user} -g ${cfg.xo.group} \
      "${cfg.xo.home}" \
      "${cfg.xo.appDir}" \
      "${cfg.xo.cacheDir}" \
      "${cfg.xo.dataDir}" \
      "${cfg.xo.tempDir}" \
      "${cfg.xo.home}/.config" \
      "${cfg.xo.home}/.config/xo-server"
    
    # Create /etc/xo-server as root (needs to be done before we drop to user)
    if [ ! -d "/etc/xo-server" ]; then
      install -d -m 0755 "/etc/xo-server"
    fi

    # Sync source into app dir
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude node_modules/ --exclude .git/ \
      "${xoSource}/" "${cfg.xo.appDir}/"
    chmod -R u+rwX "${cfg.xo.appDir}"
    cd "${cfg.xo.appDir}"

    # Fix SMB handler registration - mount.cifs -V exits with code 1 on NixOS
    echo "Patching SMB handler registration..."
    if [ -f @xen-orchestra/fs/src/index.js ]; then
      # The issue: mount.cifs -V returns exit code 1 due to setuid warning
      # Replace the strict check with one that ignores exit code 1
      sed -i "s/execa\.sync('mount\.cifs', \['-V'\])/execa.sync('mount.cifs', ['-V'], { reject: false })/" @xen-orchestra/fs/src/index.js
      echo "SMB handler patch applied"
    fi

    # Initialize minimal git repo if needed (some build tools expect it)
    if [ ! -d ".git" ]; then
      echo "Initializing minimal git repository for build tooling..."
      ${pkgs.git}/bin/git init -q
      ${pkgs.git}/bin/git config user.email "xoa-builder@localhost"
      ${pkgs.git}/bin/git config user.name "XOA Builder"
      ${pkgs.git}/bin/git add -A || true
      ${pkgs.git}/bin/git commit -q -m "imported snapshot" || true
    fi

    # Environment configuration
    export HOME="${cfg.xo.home}"
    export XDG_CACHE_HOME="${cfg.xo.cacheDir}"
    export YARN_CACHE_FOLDER="${cfg.xo.cacheDir}"
    export NPM_CONFIG_CACHE="${cfg.xo.cacheDir}/npm"
    export NODE_OPTIONS="--max-old-space-size=4096"
    export CI="true"
    export YARN_ENABLE_IMMUTABLE_INSTALLS=false
    export PYTHON="${pkgs.python3}/bin/python3"

    # Don't force esbuild binary - let yarn install the correct version
    # export ESBUILD_BINARY_PATH="${pkgs.esbuild}/bin/esbuild"

    # CRITICAL: LD_LIBRARY_PATH for native module compilation
    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    
    # Log output
    LOG="${cfg.xo.appDir}/.last-build.log"
    exec > >(tee -a "$LOG") 2>&1
    
    echo "=== Xen Orchestra Build Started ==="
    echo "Node version: $(${node}/bin/node --version)"
    echo "Yarn version: $(${yarn}/bin/yarn --version)"
    echo "Source: ${xoSource}"
    echo "Target: ${cfg.xo.appDir}"
    
    # Install dependencies
    echo "[1/3] Installing dependencies..."
    ${yarn}/bin/yarn install --network-timeout 300000 || \
      ${yarn}/bin/yarn install --frozen-lockfile --network-timeout 300000
    
    # Build
    echo "[2/3] Building..."
    ${yarn}/bin/yarn build
  '' + lib.optionalString cfg.xo.enableV6Preview ''

    # Build v6 preview
    echo "[2.5/3] Building v6 preview..."
    cd @xen-orchestra/web
    ${yarn}/bin/yarn build
    cd ..
  '' + ''

    # Patch native modules to include FUSE library paths
    echo "[3/4] Patching native modules..."
    find node_modules -name "*.node" -type f 2>/dev/null | while read -r nodefile; do
      echo "Patching $nodefile..."
      ${pkgs.patchelf}/bin/patchelf --set-rpath "${pkgs.fuse.out}/lib:${pkgs.fuse3.out}/lib:${pkgs.stdenv.cc.cc.lib}/lib" "$nodefile" 2>/dev/null || true
    done

    # Verify critical artifacts
    echo "[4/4] Verifying build artifacts..."
    if [ ! -f packages/xo-web/dist/index.html ]; then
      echo "ERROR: xo-web/dist/index.html not found!" >&2
      exit 1
    fi

    if [ ! -f packages/xo-server/dist/cli.mjs ] && [ ! -f packages/xo-server/dist/cli.js ]; then
      echo "ERROR: xo-server CLI not found!" >&2
      exit 1
    fi
  '' + lib.optionalString cfg.xo.enableV6Preview ''

    if [ ! -f @xen-orchestra/web/dist/index.html ]; then
      echo "ERROR: @xen-orchestra/web/dist/index.html not found!" >&2
      exit 1
    fi
  '' + ''
    
    echo "=== Build Complete ==="
  '';

  # Wrapper for Node with FUSE libraries
  nodeWithFuse = pkgs.writeShellScriptBin "node-with-fuse" ''
    export LD_LIBRARY_PATH="${pkgs.fuse.out}/lib:${pkgs.fuse3.out}/lib:${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ${node}/bin/node "$@"
  '';

  # Start script for xo-server
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${cfg.xo.home}"
    export NODE_ENV="production"

    cd "${cfg.xo.appDir}"

    # Find the CLI entry point
    if [ -f packages/xo-server/dist/cli.mjs ]; then
      CLI="packages/xo-server/dist/cli.mjs"
    elif [ -f packages/xo-server/dist/cli.js ]; then
      CLI="packages/xo-server/dist/cli.js"
    else
      echo "ERROR: Cannot find xo-server CLI!" >&2
      exit 1
    fi

    echo "Starting XO-server from $CLI..."
    exec ${nodeWithFuse}/bin/node-with-fuse "$CLI" "$@"
  '';

in
{
  options.xoa = {
    enable = mkEnableOption "Xen Orchestra from source";

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
      
      appDir = mkOption {
        type = types.path;
        default = "${xoHome}/xen-orchestra";
        description = "XO application directory";
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
      
      webMountDir = mkOption {
        type = types.path;
        default = "${xoHome}/xen-orchestra/packages/xo-web/dist";
        description = "Web UI mount directory";
      };

      webMountDirv6 = mkOption {
        type = types.path;
        default = "${xoHome}/xen-orchestra/@xen-orchestra/web/dist";
        description = "Web UI mount directory for v6 preview";
      };

      enableV6Preview = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Xen Orchestra v6 preview at /v6";
      };

      buildIsolation = mkOption {
        type = types.bool;
        default = false;
        description = "Enable network isolation during build";
      };
      
      extraServerEnv = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for xo-server";
      };
    };
  };

  config = mkIf cfg.enable {
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

    # System packages needed by XO
    environment.systemPackages = with pkgs; [
      nodejs_20 yarn git rsync pkg-config python3 gcc gnumake micro openssl
      fuse zlib libpng xen lvm2 esbuild
    ];

    # TLS certificate generation service (conditional)
    systemd.services.xo-bootstrap = mkIf cfg.xo.ssl.enable {
      description = "XO TLS certificate generation";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = genCerts;
      };
    };

    # Build service
    systemd.services.xo-build = {
      description = "Build Xen Orchestra from source";
      after = [ "network-online.target" ] ++ lib.optional cfg.xo.ssl.enable "xo-bootstrap.service";
      wants = [ "network-online.target" ];
      requires = [ "redis-xo.service" ] ++ lib.optional cfg.xo.ssl.enable "xo-bootstrap.service";

      path = with pkgs; [
        git nodejs_20 yarn python3 gcc gnumake pkg-config
        coreutils findutils bash esbuild patchelf
        # Mount utilities must be available at build time for handler registration
        nfs-utils cifs-utils util-linux
      ];
      
      environment = {
        HOME = cfg.xo.home;
        PYTHON = "${pkgs.python3}/bin/python3";
      };
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.xo.user;
        Group = cfg.xo.group;
        WorkingDirectory = cfg.xo.appDir;
        StateDirectory = "xo";
        CacheDirectory = "xo";

        ReadWritePaths = [
          cfg.xo.appDir
          cfg.xo.cacheDir
          cfg.xo.dataDir
          cfg.xo.tempDir
          cfg.xo.home
          "/etc/xo-server"
        ] ++ lib.optional cfg.xo.ssl.enable cfg.xo.ssl.dir;

        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.xo.user} -g ${cfg.xo.group} ${cfg.xo.appDir}"
          "+${pkgs.coreutils}/bin/chown -R ${cfg.xo.user}:${cfg.xo.group} ${cfg.xo.home}"
        ];

        ExecStart = buildXO;
        TimeoutStartSec = "45min";
        LimitNOFILE = 1048576;
      } // lib.optionalAttrs cfg.xo.buildIsolation {
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        PrivateNetwork = false;
      };
    };

    # XO Server service
    systemd.services.xo-server = {
      description = "Xen Orchestra Server";
      after = [ 
        "systemd-tmpfiles-setup.service" 
        "network-online.target" 
        "redis-xo.service" 
        "xo-build.service"
      ] ++ lib.optional cfg.xo.ssl.enable "xo-bootstrap.service";
      
      wants = [ "network-online.target" "redis-xo.service" "xo-build.service" ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "xo-build.service" "redis-xo.service" ];
      
      # Sudo wrapper must be first in path to intercept sudo calls and handle env vars
      path = [ sudoWrapper ] ++ (with pkgs; [
        util-linux git openssl xen lvm2 coreutils
        nfs-utils cifs-utils  # For NFS and SMB remote storage handlers
      ]);
      
      # Environment for xo-server
      environment = cfg.xo.extraServerEnv // {
        HOME = cfg.xo.home;
        XDG_CONFIG_HOME = "${cfg.xo.home}/.config";
        XDG_CACHE_HOME = cfg.xo.cacheDir;
        NODE_ENV = "production";
        LD_LIBRARY_PATH = "${pkgs.fuse.out}/lib:${pkgs.fuse3.out}/lib:${pkgs.stdenv.cc.cc.lib}/lib";
      };

      serviceConfig = {
        User = cfg.xo.user;
        Group = cfg.xo.group;

        WorkingDirectory = cfg.xo.appDir;
        StateDirectory = "xo";
        CacheDirectory = "xo";
        LogsDirectory = "xo";
        RuntimeDirectory = "xo xo-server";

        # PATH is automatically built from the 'path' directive above
        # Don't override it here to ensure our sudo wrapper is found first

        # Copy default config if none exists (runs as root due to '+' prefix)
        ExecStartPre = [
          "+${pkgs.writeShellScript "setup-xo-config" ''
            if [ ! -f /etc/xo-server/config.toml ]; then
              cp ${xoDefaultConfig} /etc/xo-server/config.toml
              chown ${cfg.xo.user}:${cfg.xo.group} /etc/xo-server/config.toml
              chmod 0640 /etc/xo-server/config.toml
            fi
          ''}"
        ];

        ExecStart = "${startXO} --config /etc/xo-server/config.toml";
        
        Restart = "on-failure";
        RestartSec = 10;
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
          cfg.xo.appDir
          cfg.xo.cacheDir
          cfg.xo.dataDir
          cfg.xo.tempDir
          "/etc/xo-server"
          config.xoa.storage.mountsDir
          "/run/lock"           # LVM lock files
          "/run/redis-xo"       # Redis socket
          "/dev"                # Device access for LVM/storage operations
          "/sys"                # Sysfs access for xenstore
          "/var/log"            # Sudo audit logs
        ];
        
        LimitNOFILE = 1048576;
      };
    };
    
    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d ${cfg.xo.home}                          0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.appDir}                        0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.cacheDir}                      0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.dataDir}                       0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.tempDir}                       0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${config.xoa.storage.mountsDir}         0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.home}/.config                  0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.home}/.config/xo-server        0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d /etc/xo-server                          0755 root root - -"
    ] ++ lib.optionals cfg.xo.ssl.enable [
      "d ${cfg.xo.ssl.dir}                       0755 root root - -"
    ];
  };
}
