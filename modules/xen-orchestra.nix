{ config, lib, pkgs, xoSrc ? null, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.xoa.xo;

  # If provided via flake specialArgs, use it by default (centralized pinning)
  defaultSrcPath = if xoSrc != null then xoSrc else null;
  
  # Toolchain & tools
  node = pkgs.nodejs_20;
  yarn = pkgs.yarn;
  rsync = pkgs.rsync;
  openssl = pkgs.openssl;
  
  # One-shot cert generation script (runs as the xo user)
  genCerts = pkgs.writeShellScript "xo-gen-certs.sh" ''
    set -euo pipefail
    umask 077
    # Ensure target dir exists and is owned by xo
    install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${cfg.ssl.dir}"
    # Create only if missing
    if [ ! -s "${cfg.ssl.key}" ] || [ ! -s "${cfg.ssl.cert}" ]; then
      ${openssl}/bin/openssl req -x509 -newkey rsa:4096 -sha256 -days 825 \
        -nodes -subj "/CN=${cfg.host}" \
        -keyout "${cfg.ssl.key}" \
        -out "${cfg.ssl.cert}"
      chown ${cfg.user}:${cfg.group} "${cfg.ssl.key}" "${cfg.ssl.cert}"
      chmod 0600 "${cfg.ssl.key}"
      chmod 0644 "${cfg.ssl.cert}"
    fi
  '';

  xoSource = if cfg.srcPath != null then cfg.srcPath else pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo = "xen-orchestra";
    rev = cfg.srcRev;
    hash = cfg.srcHash;
  };

  # Source to use in build
  src = xoSource;

  # Where XO's "home" lives (parent of appDir)
  xoHome = builtins.dirOf cfg.appDir;

    # Build script: copy sources into writable appDir, install deps & build
  buildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022
    install -d -m0750 -o ${cfg.user} -g ${cfg.group} "${cfg.appDir}" "${cfg.cacheDir}"
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete --exclude 'node_modules/' "${xoSource}/" "${cfg.appDir}/"
    chmod -R u+rwX "${cfg.appDir}"
    cd "${cfg.appDir}"
    # Ensure a VCS context for packages/xo-server/.babelrc.cjs (it calls `git rev-parse --short HEAD`)
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git init -q
      git config user.email "xo@nixos"
      git config user.name  "XO Build (NixOS)"
      git add -A
      git commit -q -m "NixOS build snapshot" --no-gpg-sign
    fi

    # --- Environment (also set at unit level, but keep here for clarity) ---
    export HOME="${cfg.home}"
    export XDG_CACHE_HOME="${cfg.cacheDir}"
    export YARN_CACHE_FOLDER="${cfg.cacheDir}"
    export NPM_CONFIG_CACHE="${cfg.cacheDir}/npm"
    export YARN_PRODUCTION="false"
    export npm_config_production="false"
    export ESBUILD_BINARY_PATH="${pkgs.esbuild}/bin/esbuild"
    export NODE_OPTIONS="--max-old-space-size=4096"
    export TURBO_TELEMETRY_DISABLED="1"
    export TURBO_CACHE_DIR="${cfg.cacheDir}/turbo"
    export CI="true" FORCE_COLOR="0" TERM="dumb"

    # --- Tooling versions (helpful in logs) ---
    ${yarn}/bin/yarn --version || true
    ${node}/bin/node --version || true

    # --- Install dependencies (with devDeps) ---
    ${yarn}/bin/yarn install --check-files --non-interactive --network-timeout 600000

    # --- Find workspace names dynamically (robust against upstream renames) ---
    WS_WEB="$(${node}/bin/node -e 'console.log(require("./packages/xo-web/package.json").name)')"
    WS_SRV="$(${node}/bin/node -e 'console.log(require("./packages/xo-server/package.json").name)')"

    # --- Try fast path: Turbo build with filters (web first, then server) ---
    LOG="${cfg.appDir}/.last-build.log"
    if ${yarn}/bin/yarn -s run turbo run build --no-daemon --continue \
         --filter "$WS_WEB" --filter "$WS_SRV" 2>&1 | tee "$LOG"; then
      exit 0
    fi

    echo "Turbo failed, falling back to per-workspace builds…" | tee -a "$LOG"
    # Build just what we need, in order, without Turbo:
    ${yarn}/bin/yarn -s workspace "$WS_WEB" run build 2>&1 | tee -a "$LOG"
    ${yarn}/bin/yarn -s workspace "$WS_SRV" run build 2>&1 | tee -a "$LOG"
  '';

  # Start script: run the built XO server
  startScript = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${xoHome}"
    cd "${cfg.appDir}"
    exec ${node}/bin/node "${cfg.appDir}/packages/xo-server/dist/cli.mjs"
  '';
in
{
  options.xoa.xo = {
    enable = mkEnableOption "Xen Orchestra (build from sources)";
    
    srcPath = mkOption {
      type = types.nullOr types.path;
      default = defaultSrcPath;
      description = ''
        If set, use this path as the Xen Orchestra sources (e.g. a flake input
        pinned in flake.lock or a local checkout). When non-null, srcRev/srcHash are ignored.
      '';
    };
    
    srcRev = mkOption {
      type = types.str;
      default = "";
      description = "Git revision to build (used only when srcPath=null).";
    };
    
    srcHash = mkOption {
      type = types.str;
      default = "";
      description = "sha256 for the above revision (used only when srcPath=null).";
    };
    
    user = mkOption {
      type = types.str;
      default = "xo";
      description = "User account for running XO services.";
    };
    
    group = mkOption {
      type = types.str;
      default = "xo";
      description = "Group for XO services.";
    };
    
    home = mkOption {
      type = types.path;
      default = "/var/lib/xo";
      description = "Home directory for XO user.";
    };
    
    appDir = mkOption {
      type = types.path;
      default = "/var/lib/xo/app";
      description = "Directory containing XO application files.";
    };
    
    cacheDir = mkOption {
      type = types.path;
      default = "/var/cache/xo/yarn-cache";
      description = "Cache directory for yarn/npm.";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/xo/data";
      description = "Data directory for XO (backups metadata, job logs, etc).";
    };
    
    tempDir = mkOption {
      type = types.path;
      default = "/var/lib/xo/tmp";
      description = "Temporary directory for XO operations.";
    };
    
    mountsDir = mkOption {
      type = types.path;
      default = "/var/lib/xo/mounts";
      description = "Directory for mounting remote shares and VHD files.";
    };
    
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Hostname/IP to bind the HTTP server to.";
    };
    
    port = mkOption {
      type = types.port;
      default = 80;
      description = "HTTP port for XO web interface.";
    };
    
    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "HTTPS port for XO web interface (when SSL enabled).";
    };

    ssl = {
      enable = mkEnableOption "Enable TLS for xo-server" // { default = true; };
      
      dir = mkOption {
        type = types.path;
        default = "/etc/ssl/xo";
        description = "Directory containing TLS cert/key for xo-server.";
      };
      
      key = mkOption {
        type = types.path;
        default = "/etc/ssl/xo/key.pem";
        description = "Path to TLS private key.";
      };
      
      cert = mkOption {
        type = types.path;
        default = "/etc/ssl/xo/certificate.pem";
        description = "Path to TLS certificate.";
      };
    };

    extraServerEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment variables for xo-server.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.srcPath != null) || (cfg.srcRev != "" && cfg.srcHash != "");
        message = "Provide xoa.xo.srcPath OR both xoa.xo.srcRev and xoa.xo.srcHash.";
      }
    ];

    # Packages for convenience
    environment.systemPackages = with pkgs; [
      node yarn git rsync openssl pkg-config python3 gcc gnumake
      libpng zlib nfs-utils cifs-utils
    ];

    # XO server configuration file
    environment.etc."xo-server/config.toml".text = ''
      # Xen Orchestra Server Configuration
      # Managed by NixOS - edit /etc/xo-server/config.toml and restart xo-server.service

      # HTTP listen configuration
      [http.listen]
      hostname = "${cfg.host}"
      port = ${toString cfg.port}

      # HTTPS configuration
      ${lib.optionalString cfg.ssl.enable ''
      [http.listen.1]
      hostname = "${cfg.host}"
      port = ${toString cfg.httpsPort}
      certificate = "${cfg.ssl.cert}"
      key = "${cfg.ssl.key}"
      ''}

      # Redis connection (Unix socket)
      [redis]
      socket = "/run/redis-xo/redis.sock"

      # Data storage paths
      [datadir]
      path = "${cfg.dataDir}"

      [tempdir]
      path = "${cfg.tempDir}"

      # Mount directory for remote shares and VHD operations
      [mountsDir]
      path = "${cfg.mountsDir}"

      # Authentication configuration
      [authentication]
      defaultTokenValidity = "30 days"

      # Logs configuration
      [logs]
      level = "info"
    '';

    # Dedicated Redis instance for XO
    services.redis.servers."xo" = {
      enable = true;
      user = cfg.user;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings = {
        port = 0;  # Disable TCP, Unix socket only
        databases = 16;
      };
    };

    # Generate self-signed certs once
    systemd.services.xo-bootstrap = mkIf cfg.ssl.enable {
      description = "XO bootstrap (generate HTTPS self-signed certs if missing)";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ReadWritePaths = [ cfg.ssl.dir ];
        ExecStart = genCerts;
      };
    };

    # Build: compile the monorepo with yarn/node-gyp toolchain available
    systemd.services.xo-build = {
      description = "Build Xen Orchestra from source";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ lib.optional cfg.ssl.enable "xo-bootstrap.service";
      requires = lib.optional cfg.ssl.enable "xo-bootstrap.service";

      path = with pkgs; [
        nodejs_20 yarn gnumake gcc python3 pkg-config git patch
        fuse fuse3 libtool autoconf automake binutils esbuild
      ];

      environment = {
        HOME = xoHome;
        XDG_CACHE_HOME = builtins.dirOf cfg.cacheDir;
        YARN_CACHE_FOLDER = cfg.cacheDir;
        NPM_CONFIG_CACHE = "${cfg.cacheDir}/npm";
        npm_config_nodedir = "${pkgs.nodejs_20}/include/node";
        YARN_PRODUCTION = "false";
        npm_config_production = "false";
        npm_config_build_from_source = "true";
        PYTHON = "${pkgs.python3}/bin/python3";
        PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [ pkgs.fuse.dev pkgs.fuse3.dev ];
        CPATH = "${pkgs.fuse.dev}/include:${pkgs.fuse3.dev}/include";
        CFLAGS = "-I${pkgs.fuse.dev}/include -I${pkgs.fuse3.dev}/include";
        CXXFLAGS = "-I${pkgs.fuse.dev}/include -I${pkgs.fuse3.dev}/include";
        LDFLAGS = "-L${pkgs.fuse.out}/lib -L${pkgs.fuse3.out}/lib";
        ESBUILD_BINARY_PATH = "${pkgs.esbuild}/bin/esbuild";
        NPM_CONFIG_UPDATE_NOTIFIER = "false";
        NODE_OPTIONS = "--max-old-space-size=4096";
        TURBO_TELEMETRY_DISABLED = "1";
        TURBO_CACHE_DIR = "${cfg.cacheDir}/turbo";
        CI = "true";
        FORCE_COLOR = "0";
        LIBRARY_PATH = "${pkgs.fuse.out}/lib:${pkgs.fuse3.out}/lib";
        LD_LIBRARY_PATH = "${pkgs.fuse.out}/lib:${pkgs.fuse3.out}/lib";
      };

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;

        StateDirectory = "xo";
        StateDirectoryMode = "0750";
        CacheDirectory = "xo";
        CacheDirectoryMode = "0750";

        WorkingDirectory = cfg.appDir;
        LimitNOFILE = 1048576;
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${cfg.appDir} ${cfg.cacheDir}"
          "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.appDir} ${cfg.cacheDir}"
          "+${pkgs.coreutils}/bin/chmod -R u+rwX ${cfg.appDir} ${cfg.cacheDir}"
        ];
        
        ExecStart = buildScript;

        ReadWritePaths = [ cfg.appDir cfg.cacheDir ] ++ lib.optional cfg.ssl.enable cfg.ssl.dir;
        PrivateTmp = true;
        
        # Timeout for build (can take a while on first run)
        TimeoutStartSec = "30min";
      };
    };

    # Run server after build
    systemd.services.xo-server = {
      description = "Xen Orchestra server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "xo-build.service" ];
     # If you order after network-online, you should also want it:
      wants    = [ "network-online.target" ];
      after    = [ "xo-build.service" "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        StateDirectory = "xo";
        StateDirectoryMode = "0750";
        CacheDirectory = "xo";
        CacheDirectoryMode = "0750";

        WorkingDirectory = cfg.appDir;
        ExecStart = startScript;
        
        Restart = "on-failure";
        RestartSec = 10;

        # Don't start until compiled artifacts exist
        ConditionPathExists = "${cfg.appDir}/packages/xo-server/dist/cli.mjs";

        # Allow writing to necessary directories
        ReadWritePaths = [
          cfg.appDir
          cfg.cacheDir
          cfg.dataDir
          cfg.tempDir
          cfg.mountsDir
        ] ++ lib.optional cfg.ssl.enable cfg.ssl.dir;
        # Allow non-root 'xo' to bind to privileged port 443:
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;

        PrivateTmp = true;
        
        # Security hardening (while allowing mount operations)
        ProtectSystem = "strict";
        ProtectHome = true;
        
        # Healthcheck
        TimeoutStartSec = "5min";
      };

      environment = cfg.extraServerEnv // {
        HOME = xoHome;
        NODE_ENV = "production";
      };
    };

    # Ensure all XO directories exist with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.home}      0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.appDir}    0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.cacheDir}  0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}   0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.tempDir}   0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.mountsDir} 0750 ${cfg.user} ${cfg.group} - -"
    ] ++ lib.optionals cfg.ssl.enable [
      "d ${cfg.ssl.dir}   0750 ${cfg.user} ${cfg.group} - -"
    ];
  };
}