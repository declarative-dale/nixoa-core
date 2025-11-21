{ config, lib, pkgs, xoSrc ? null, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.xoa;

  node   = pkgs.nodejs_20;
  yarn   = pkgs.yarn;
  rsync  = pkgs.rsync;
  openssl = pkgs.openssl;
  
  # Fixed xo-server config with proper HTTPS setup
  xoDefaultConfig = pkgs.writeText "xo-config-default.toml" (''
    [http]
    hostname = '${cfg.xo.host}'
    port = ${toString cfg.xo.port}
  '' + lib.optionalString cfg.xo.ssl.enable ''
    redirectToHttps = true

    [http.https]
    enabled = true
    port = ${toString cfg.xo.httpsPort}
    certificate = '${cfg.xo.ssl.cert}'
    key = '${cfg.xo.ssl.key}'
  '' + ''

    [http.mounts]
    '/' = '${cfg.xo.webMountDir}'

    [redis]
    socket = "/run/redis-xo/redis.sock"
    
    [authentication]
    defaultTokenValidity = "30 days"

    [logs]
    level = "info"
  '');

  # Centralized bootstrap: creates directories, cleans build artifacts, generates certs
  bootstrapScript = pkgs.writeShellScript "xo-bootstrap.sh" ''
    set -euo pipefail
    umask 077
    
    # Create all required directories
    install -d -m 0750 -o ${cfg.xo.user} -g ${cfg.xo.group} \
      "${cfg.xo.home}" \
      "${cfg.xo.appDir}" \
      "${cfg.xo.cacheDir}" \
      "${cfg.xo.dataDir}" \
      "${cfg.xo.tempDir}" \
      "${cfg.xo.home}/.config" \
      "${cfg.xo.home}/.config/xo-server"
    
    # Clean build artifacts that might have wrong ownership (from root-owned server)
    # This must happen as root before the xo user tries to build
    if [ -d "${cfg.xo.appDir}" ]; then
      echo "Cleaning existing build artifacts..."
      rm -rf "${cfg.xo.appDir}"/.turbo \
             "${cfg.xo.appDir}"/node_modules \
             "${cfg.xo.appDir}"/packages/*/dist \
             "${cfg.xo.appDir}"/packages/*/.turbo \
             "${cfg.xo.appDir}"/packages/*/node_modules 2>/dev/null || true
      
      # Ensure correct ownership
      chown -R ${cfg.xo.user}:${cfg.xo.group} "${cfg.xo.appDir}" || true
    fi
    
    ${lib.optionalString cfg.xo.ssl.enable ''
      # Create SSL directory
      install -d -m 0750 -o ${cfg.xo.user} -g ${cfg.xo.group} "${cfg.xo.ssl.dir}"
      
      # Generate self-signed certs if missing
      if [ ! -s "${cfg.xo.ssl.key}" ] || [ ! -s "${cfg.xo.ssl.cert}" ]; then
        ${openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
          -keyout "${cfg.xo.ssl.key}" -out "${cfg.xo.ssl.cert}" \
          -subj "/CN=${config.networking.hostName}" \
          -addext "subjectAltName=DNS:${config.networking.hostName}"
        chown ${cfg.xo.user}:${cfg.xo.group} "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}"
        chmod 0640 "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}"
      fi
    ''}
  '';

  # Build script: Simplified - cleanup now happens in bootstrap
  buildXO = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022

    # Sync source into app dir
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude node_modules/ --exclude .git/ \
      "${xoSource}/" "${cfg.xo.appDir}/"
    chmod -R u+rwX "${cfg.xo.appDir}"
    cd "${cfg.xo.appDir}"
    
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
    export NPM_CONFIG_CACHE="${cfg.xo.cacheDir}"
    export NODE_OPTIONS="--max-old-space-size=4096"
    export CI="true"
    export YARN_ENABLE_IMMUTABLE_INSTALLS=true

    # CRITICAL: LD_LIBRARY_PATH for native module compilation
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [
      pkgs.fuse
      pkgs.zlib
      pkgs.libpng
      pkgs.openssl
    ]}:''${LD_LIBRARY_PATH:-}"

    # Set PATH to include build tools and node_modules/.bin
    export PATH="${lib.makeBinPath [
      node
      yarn
      pkgs.git
      pkgs.python3
      pkgs.gcc
      pkgs.gnumake
      pkgs.pkg-config
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
    ]}:$PWD/node_modules/.bin:$PATH"

    # Python for node-gyp
    export PYTHON="${pkgs.python3}/bin/python3"

    # Rotate build log (keep only last build)
    LOG="${cfg.xo.appDir}/.last-build.log"
    rm -f "$LOG"
    exec > >(tee "$LOG") 2>&1

    echo "=== XO Build started at $(date -Iseconds) ==="
    echo "Build directory: ${cfg.xo.appDir}"
    START_TIME=$(date +%s)

    echo "Yarn version:"
    ${yarn}/bin/yarn --version

    # Install dependencies (NODE_ENV=development gets devDependencies like turbo)
    echo "Installing dependencies (including devDependencies)..."
    NODE_ENV=development ${yarn}/bin/yarn install --frozen-lockfile --network-timeout 300000 || \
      NODE_ENV=development ${yarn}/bin/yarn install --network-timeout 300000

    # Build packages (NODE_ENV=production for optimized build)
    echo "Building XO packages..."
    NODE_ENV=production ${yarn}/bin/yarn build

    # Verify build artifacts
    echo "Verifying build artifacts..."
    test -f packages/xo-web/dist/index.html || { 
      echo "ERROR: xo-web/dist/index.html missing" >&2
      exit 1
    }
    test -f packages/xo-server/dist/cli.mjs || test -f packages/xo-server/dist/cli.js || { 
      echo "ERROR: xo-server CLI not found in dist/" >&2
      exit 1
    }

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    echo "=== Build completed successfully in ''${DURATION}s at $(date -Iseconds) ==="
  '';

  # Robustly locate XO CLI entrypoint with error handling
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    cd "${cfg.xo.appDir}"
    
    # Set NODE_ENV for runtime
    export NODE_ENV=production
    export PATH="${node}/bin:$PATH"
    
    # CRITICAL: LD_LIBRARY_PATH for native modules (fuse-native, libvhdi, etc.)
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [
      pkgs.fuse
      pkgs.zlib
      pkgs.libpng
      pkgs.openssl
    ]}:''${LD_LIBRARY_PATH:-}"
    
    CLI=""
    if [ -f packages/xo-server/dist/cli.mjs ]; then
      CLI="packages/xo-server/dist/cli.mjs"
    elif [ -f packages/xo-server/dist/cli.js ]; then
      CLI="packages/xo-server/dist/cli.js"
    else
      CLI=$(find packages/xo-server/dist -name "cli.mjs" -o -name "cli.js" 2>/dev/null | head -1)
    fi
    
    if [ -z "$CLI" ]; then
      echo "ERROR: XO CLI entrypoint not found in packages/xo-server/dist" >&2
      exit 1
    fi
    
    exec ${node}/bin/node "$CLI"
  '';

  xoSource =
    if cfg.xo.srcPath != null then cfg.xo.srcPath
    else if cfg.xo.srcRev != "" && cfg.xo.srcHash != "" then
      pkgs.fetchFromGitHub {
        owner = "vatesfr";
        repo = "xen-orchestra";
        rev = cfg.xo.srcRev;
        hash = cfg.xo.srcHash;
      }
    else if xoSrc != null then xoSrc
    else throw "xoa.xo.srcPath OR (xoa.xo.srcRev + xoa.xo.srcHash) must be set.";
in
{
  options.xoa = {
    enable = mkEnableOption "Xen Orchestra CE stack";

    admin = {
      user = mkOption { 
        type = types.str; 
        default = "xoa";
        description = "Admin user with sudo access for system management";
      };
      sshAuthorizedKeys = mkOption { 
        type = types.listOf types.str; 
        default = [];
        description = "SSH public keys for admin user";
      };
    };

    xo = {
      user  = mkOption { 
        type = types.str; 
        default = "xo";
        description = "Service user that runs XO server (no sudo, limited privileges)";
      };
      group = mkOption { 
        type = types.str; 
        default = "xo";
        description = "Service group for XO";
      };

      home     = mkOption { type = types.path; default = "/var/lib/xo-server"; };
      appDir   = mkOption { type = types.path; default = "/var/lib/xo-server/app"; };
      cacheDir = mkOption { type = types.path; default = "/var/cache/xo-server/yarn-cache"; };
      dataDir  = mkOption { type = types.path; default = "/var/lib/xo-server/data"; };
      tempDir  = mkOption { type = types.path; default = "/var/lib/xo-server/tmp"; };
      webMountDir = mkOption { type = types.path; default = "/var/lib/xo-server/app/packages/xo-web/dist"; };

      host      = mkOption { type = types.str; default = "0.0.0.0"; };
      port      = mkOption { type = types.port; default = 80; };
      httpsPort = mkOption { type = types.port; default = 443; };

      ssl.enable = mkEnableOption "TLS for XO" // { default = true; };
      ssl.dir  = mkOption { type = types.path; default = "/etc/ssl/xo"; };
      ssl.key  = mkOption { type = types.path; default = "/etc/ssl/xo/key.pem"; };
      ssl.cert = mkOption { type = types.path; default = "/etc/ssl/xo/certificate.pem"; };

      srcPath = mkOption { type = types.nullOr types.path; default = null; };
      srcRev  = mkOption { type = types.str; default = ""; };
      srcHash = mkOption { type = types.str; default = ""; };

      buildIsolation = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Restrict network access during build.
          Disabled by default since IPAddressAllow needs IPs not hostnames.
        '';
      };

      extraServerEnv = mkOption { type = types.attrsOf types.str; default = {}; };
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.xo.srcPath != null) || (cfg.xo.srcRev != "" && cfg.xo.srcHash != "") || (xoSrc != null);
      message = "Provide xoa.xo.srcPath OR both xoa.xo.srcRev and xoa.xo.srcHash (or provide xoSrc flake input).";
    }];

    # Admin user for SSH and system management
    users.users.${cfg.admin.user} = {
      isNormalUser = true;
      description = "XOA Administrator";
      extraGroups = [ "wheel" "networkmanager" "systemd-journal" ];
      openssh.authorizedKeys.keys = cfg.admin.sshAuthorizedKeys;
      hashedPassword = "!";
    };

    # XO service user
    users.groups.${cfg.xo.group} = {};
    users.users.${cfg.xo.user} = {
      isSystemUser = true;
      description = "Xen Orchestra service user";
      createHome = true;
      home  = cfg.xo.home;
      group = cfg.xo.group;
      shell = "${pkgs.shadow}/bin/nologin";
      extraGroups = [ "fuse" ];
    };

    # Redis for XO via Unix socket
    services.redis.servers."xo" = {
      enable = true;
      user = cfg.xo.user;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings = { port = 0; databases = 16; };
    };

    # SSH server (keys-only)
    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
        AllowUsers = [ cfg.admin.user ];
      };
    };

    # Xen guest agent
    systemd.packages = [ pkgs.xen-guest-agent ];
    systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];

    # System packages
    environment.systemPackages = with pkgs; [
      nodejs_20 yarn git rsync pkg-config python3 gcc gnumake openssl jq micro
      fuse zlib libpng xen lvm2
    ];

    # Bootstrap service: creates directories, cleans artifacts, generates certs
    systemd.services.xo-bootstrap = {
      description = "XO Bootstrap: Directories, cleanup, and TLS";
      wantedBy = [ "multi-user.target" ];
      before = [ "xo-build.service" "xo-server.service" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
        ExecStart = bootstrapScript;
      };
    };

    # Build service
    systemd.services.xo-build = {
      description = "Build Xen Orchestra from source";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "xo-bootstrap.service" ];
      wants = [ "network-online.target" ];
      requires = [ "redis-xo.service" "xo-bootstrap.service" ];
      path = with pkgs; [ git ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.xo.user;
        Group = cfg.xo.group;
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv
          ++ [ "HOME=${cfg.xo.home}" ];
        ReadWritePaths = [
          cfg.xo.appDir 
          cfg.xo.cacheDir 
          cfg.xo.dataDir 
          cfg.xo.tempDir
        ];
        ExecStart = buildXO;
        TimeoutStartSec = "15min";
      } // lib.optionalAttrs cfg.xo.buildIsolation {
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };

    # Server service - FIXED to run as xo user with proper config permissions
    systemd.services.xo-server = {
      description = "Xen Orchestra (xo-server)";
      after = [ 
        "systemd-tmpfiles-setup.service" 
        "network-online.target" 
        "redis-xo.service" 
        "xo-build.service"
        "xo-bootstrap.service"
      ];
      wants = [ "network-online.target" "redis-xo.service" "xo-build.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ util-linux git openssl xen lvm2 ];
      
      # Create writable config directory for xo-server
      preStart = ''
        install -d -m 0755 -o ${cfg.xo.user} -g ${cfg.xo.group} /etc/xo-server

        # Copy the default config if it doesn't exist
        if [ ! -f /etc/xo-server/config.toml ]; then
          cp ${xoDefaultConfig} /etc/xo-server/config.toml
          chown ${cfg.xo.user}:${cfg.xo.group} /etc/xo-server/config.toml
          chmod 0640 /etc/xo-server/config.toml
        fi

        # Ensure SSL certs are readable by xo user
        ${lib.optionalString cfg.xo.ssl.enable ''
          if [ -f "${cfg.xo.ssl.key}" ]; then
            chown ${cfg.xo.user}:${cfg.xo.group} "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}" || true
            chmod 0640 "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}" || true
          fi
        ''}
      '';
      
      serviceConfig = {
        # Run as xo user, not root
        User = cfg.xo.user;
        Group = cfg.xo.group;
        
        WorkingDirectory = cfg.xo.appDir;
        StateDirectory = "xo-server";
        CacheDirectory = "xo-server";
        LogsDirectory = "xo-server";
        RuntimeDirectory = "xo-server";
        
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv
          ++ [ "HOME=${cfg.xo.home}" ];
        
        # Use config at /etc/xo-server/config.toml
        ExecStart = "${startXO} --config /etc/xo-server/config.toml";
        
        Restart = "on-failure";
        RestartSec = 3;
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        
        # Allow reading SSL certs
        ReadOnlyPaths = lib.optionals cfg.xo.ssl.enable [ cfg.xo.ssl.dir ];
        
        ReadWritePaths = [
          cfg.xo.home
          cfg.xo.dataDir
          cfg.xo.tempDir
          "/etc/xo-server"  # Allow writing config and temp files
        ];
        
        TimeoutStartSec = "5min";
        
        # Capabilities needed for Xen operations
        AmbientCapabilities = [ "CAP_SYS_ADMIN" "CAP_DAC_OVERRIDE" ];
        CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_DAC_OVERRIDE" ];
      };
    };

    # Config is managed in /var/lib/xo-server/config/ (writable by xo user)
    # We don't create a read-only /etc/xo-server/ config to avoid confusion
  };
}
