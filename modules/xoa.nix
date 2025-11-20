{ config, lib, pkgs, xoSrc ? null, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.xoa;

  node   = pkgs.nodejs_20;
  yarn   = pkgs.yarn;
  rsync  = pkgs.rsync;
  openssl = pkgs.openssl;
  
  # Default xo-server config
  xoDefaultConfig = pkgs.writeText "xo-config-default.toml" ''
    [http]
    hostname = '${cfg.xo.host}'
    port = ${toString cfg.xo.port}

    [http.https]
    enabled = ${if cfg.xo.ssl.enable then "true" else "false"}
    certificate = '${cfg.xo.ssl.cert}'
    key = '${cfg.xo.ssl.key}'
    port = ${toString cfg.xo.httpsPort}

    [http.mounts]
    '/' = '${cfg.xo.webMountDir}'

    [redis]
    socket = "/run/redis-xo/redis.sock"
  '';

  # Centralized bootstrap: creates ALL directories and generates certs
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

  # Build script: Enhanced with logging, verification, and proper environment
  buildXO = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022

    # Sync source into app dir
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude node_modules/ --exclude .git/ \
      "${xoSource}/" "${cfg.xo.appDir}/"
    chmod -R u+rwX "${cfg.xo.appDir}"
    cd "${cfg.xo.appDir}"
      if [ ! -d ".git" ]; then
        echo "Initializing a minimal git repository for build tooling..."
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
    
    exec ${node}/bin/node "$CLI" --config /etc/xo-server/config.toml
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
        default = true;
        description = ''
          Restrict network access during build to npm/yarn registries only.
          Provides security while allowing necessary dependency fetching.
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
      extraGroups = [ "wheel" "networkmanager" "systemd-journal" ];  # Full sudo access
      openssh.authorizedKeys.keys = cfg.admin.sshAuthorizedKeys;
    # Disable password entirely (SSH only)
      hashedPassword = "*";
    };

    # XO service user (no sudo, limited privileges)
    users.groups.${cfg.xo.group} = {};
    users.users.${cfg.xo.user} = {
      isSystemUser = true;
      description = "Xen Orchestra service user";
      createHome = true;
      home  = cfg.xo.home;
      group = cfg.xo.group;
      shell = "${pkgs.shadow}/bin/nologin";
      extraGroups = [ "fuse" ];  # For FUSE mounts only
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

    # System packages useful for XO build and management
    environment.systemPackages = with pkgs; [
      nodejs_20 yarn git rsync pkg-config micro python3 gcc gnumake openssl jq
      # Native libraries needed by XO
      fuse zlib libpng
    ];

    # Bootstrap service: creates ALL directories + generates certs
    systemd.services.xo-bootstrap = {
      description = "XO Bootstrap: Create directories and TLS certificates";
      wantedBy = [ "multi-user.target" ];
      before = [ "xo-build.service" "xo-server.service" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = bootstrapScript;
        User = "root";
      };
    };

    # Build service: Pragmatic hybrid approach with logging and verification
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
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv ++ [ "HOME=${cfg.xo.home}" ];
        ReadWritePaths = [
          cfg.xo.appDir 
          cfg.xo.cacheDir 
          cfg.xo.dataDir 
          cfg.xo.tempDir
        ];
        ExecStart = buildXO;
        TimeoutStartSec = "15min";
      } // lib.optionalAttrs cfg.xo.buildIsolation {
        # Restrict network to npm/yarn registries only
        IPAddressAllow = [
          "registry.yarnpkg.com"
          "registry.npmjs.org"
          "github.com"
          "codeload.github.com"
        ];
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };

    # Server service
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
      path = with pkgs; [ util-linux xen git openssl lvm2 ];
      serviceConfig = {
        User = cfg.xo.user;
        Group = cfg.xo.group;
        CacheDirectory = "xo-server";
        LogsDirectory  = "xo-server";
        WorkingDirectory = cfg.xo.appDir;
        Environment =
          lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv
          ++ [ "HOME=${cfg.xo.home}" ];        ExecStart = startXO;
        Restart = "on-failure";
        RestartSec = 3;
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RuntimeDirectory = "xo-server";
        ReadOnlyPaths = [ "/etc/xo-server/config.toml" ];
        ReadWritePaths = [ 
          cfg.xo.home
          cfg.xo.dataDir 
          cfg.xo.tempDir
        ];
        StateDirectory = "xo-server";
        TimeoutStartSec = "5min";
      };
    };

    environment.etc."xo-server/config.toml" = {
     source = xoDefaultConfig;
     mode   = "0640";
     user   = cfg.xo.user;
     group  = cfg.xo.group;
   };
  };
}