{ config, lib, pkgs, xoSrc ? null, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.xoa.xo;

  defaultSrcPath = if xoSrc != null then xoSrc else null;
  
  node = pkgs.nodejs_20;
  yarn = pkgs.yarn;
  rsync = pkgs.rsync;
  openssl = pkgs.openssl;
  
  genCerts = pkgs.writeShellScript "xo-gen-certs.sh" ''
    set -euo pipefail
    umask 077
    install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${cfg.ssl.dir}"
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

  xoHome = builtins.dirOf cfg.appDir;

  # Simplified build script matching xo-install.sh from XenOrchestraInstallerUpdater
  buildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022
    
    # Prepare directories
    install -d -m0750 -o ${cfg.user} -g ${cfg.group} "${cfg.appDir}" "${cfg.cacheDir}"
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude 'node_modules/' --exclude '.git/' \
      "${xoSource}/" "${cfg.appDir}/"
    chmod -R u+rwX "${cfg.appDir}"
    cd "${cfg.appDir}"

    # Environment
    export HOME="${cfg.home}"
    export XDG_CACHE_HOME="${cfg.cacheDir}"
    export YARN_CACHE_FOLDER="${cfg.cacheDir}"
    export NPM_CONFIG_CACHE="${cfg.cacheDir}/npm"
    export NODE_OPTIONS="--max-old-space-size=4096"
    export YARN_PRODUCTION="false"
    export CI="true"
    
    LOG="${cfg.appDir}/.last-build.log"
    exec > >(tee -a "$LOG") 2>&1
    
    echo "=== Xen Orchestra Build Started ===" 
    ${yarn}/bin/yarn --version
    ${node}/bin/node --version
    
    # Initialize git for build metadata
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      git init -q
      git config user.email "xo@nixos"  
      git config user.name "XO Build"
      git add -A
      git commit -q -m "NixOS build" --no-gpg-sign
    fi
    
    echo "[1/2] Installing dependencies..."
    ${yarn}/bin/yarn install --frozen-lockfile --network-timeout 300000 || \
      ${yarn}/bin/yarn install --network-timeout 300000
    
    echo "[2/2] Building..."
    ${yarn}/bin/yarn build
    
    # Verify critical artifacts
    echo "Verifying build artifacts..."
    test -f packages/xo-web/dist/index.html || { echo "ERROR: xo-web/dist missing"; exit 1; }
    test -f packages/xo-server/dist/cli.mjs || test -f packages/xo-server/dist/cli.js || \
      { echo "ERROR: xo-server/dist missing"; exit 1; }
    
    echo "=== Build Complete ==="
  '';

  startScript = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${xoHome}"
    export NODE_ENV="production"
    cd "${cfg.appDir}"
    
    # Find the CLI entry point
    if [ -f packages/xo-server/dist/cli.mjs ]; then
      CLI="packages/xo-server/dist/cli.mjs"
    elif [ -f packages/xo-server/dist/cli.js ]; then
      CLI="packages/xo-server/dist/cli.js"
    else
      CLI=$(find packages/xo-server/dist -name "cli.mjs" -o -name "cli.js" | head -1)
    fi
    
    exec ${node}/bin/node "$CLI" --config /etc/xo-server/config.toml
  '';
in
{
  options.xoa.xo = {
    enable = mkEnableOption "Xen Orchestra";
    srcPath = mkOption { type = types.nullOr types.path; default = defaultSrcPath; };
    srcRev = mkOption { type = types.str; default = ""; };
    srcHash = mkOption { type = types.str; default = ""; };
    user = mkOption { type = types.str; default = "xo"; };
    group = mkOption { type = types.str; default = "xo"; };
    home = mkOption { type = types.path; default = "/var/lib/xo"; };
    appDir = mkOption { type = types.str; default = "/var/lib/xo/app"; };
    cacheDir = mkOption { type = types.str; default = "/var/cache/xo/yarn-cache"; };
    webMountDir = mkOption { type = types.str; default = "/var/lib/xo/app/packages/xo-web/dist"; };
    dataDir = mkOption { type = types.path; default = "/var/lib/xo/data"; };
    tempDir = mkOption { type = types.path; default = "/var/lib/xo/tmp"; };
    mountsDir = mkOption { type = types.path; default = "/var/lib/xo/mounts"; };
    host = mkOption { type = types.str; default = "0.0.0.0"; };
    port = mkOption { type = types.port; default = 80; };
    httpsPort = mkOption { type = types.port; default = 443; };
    ssl = {
      enable = mkEnableOption "TLS" // { default = true; };
      dir = mkOption { type = types.path; default = "/etc/ssl/xo"; };
      key = mkOption { type = types.path; default = "/etc/ssl/xo/key.pem"; };
      cert = mkOption { type = types.path; default = "/etc/ssl/xo/certificate.pem"; };
    };
    extraServerEnv = mkOption { type = types.attrsOf types.str; default = {}; };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.srcPath != null) || (cfg.srcRev != "" && cfg.srcHash != "");
      message = "Provide srcPath OR both srcRev and srcHash.";
    }];

    environment.systemPackages = with pkgs; [
      node yarn git rsync pkg-config python3 gcc gnumake
      openssl jq nfs-utils cifs-utils
    ];
    
    environment.etc."xo-server/config.toml".text = ''
      [http]
      hostname = '${cfg.host}'
      port = ${toString cfg.port}

      [http.https]
      enabled = ${if cfg.ssl.enable then "true" else "false"}
      certificate = '${cfg.ssl.cert}'
      key = '${cfg.ssl.key}'
      port = ${toString cfg.httpsPort}
      
      [http.mounts]
      '/' = '${cfg.webMountDir}'

      [redis]
      socket = "/run/redis-xo/redis.sock"

      [datadir]
      path = "${cfg.dataDir}"

      [tempdir]
      path = "${cfg.tempDir}"

      [mountsDir]
      path = "${cfg.mountsDir}"

      [authentication]
      defaultTokenValidity = "30 days"

      [logs]
      level = "info"
    '';

    services.redis.servers."xo" = {
      enable = true;
      user = cfg.user;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings = { port = 0; databases = 16; };
    };

    systemd.services.xo-bootstrap = mkIf cfg.ssl.enable {
      description = "XO TLS certificate generation";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ReadWritePaths = [ cfg.ssl.dir ];
        ExecStart = genCerts;
      };
    };

    systemd.services.xo-build = {
      description = "Build Xen Orchestra from source";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ lib.optional cfg.ssl.enable "xo-bootstrap.service";
      requires = lib.optional cfg.ssl.enable "xo-bootstrap.service";

      path = with pkgs; [
        nodejs_20 yarn gnumake gcc python3 pkg-config git
        bash coreutils findutils esbuild
      ];

      environment = {
        HOME = xoHome;
        PYTHON = "${pkgs.python3}/bin/python3";
        ESBUILD_BINARY_PATH = "${pkgs.esbuild}/bin/esbuild";
      };

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.appDir;
        StateDirectory = "xo";
        CacheDirectory = "xo";
        LimitNOFILE = 1048576;
        
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${cfg.appDir} ${cfg.cacheDir}"
          "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.appDir} ${cfg.cacheDir}"
        ];
        
        ExecStart = buildScript;
        ReadWritePaths = [ cfg.appDir cfg.cacheDir ] ++ lib.optional cfg.ssl.enable cfg.ssl.dir;
        PrivateTmp = true;
        TimeoutStartSec = "45min";
      };
    };

    systemd.services.xo-server = {
      description = "Xen Orchestra server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "xo-build.service" "redis-xo.service" ];
      after = [ "xo-build.service" "redis-xo.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.openssl pkgs.coreutils ];

      # Environment exposed to the service
      environment = cfg.extraServerEnv // {
        HOME = xoHome;
        XDG_CONFIG_HOME = "${cfg.home}/.config";
        XDG_CACHE_HOME  = cfg.cacheDir;
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.appDir;

        # Makes /var/lib/xo and friends for us and exempts from ProtectSystem
        StateDirectory = "xo";

        # Make sure $HOME/.config/xo-server exists before starting
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${cfg.home}/.config/xo-server"
        ];

        ExecStart = startScript;

        # With ProtectSystem=strict, explicitly allow writes to needed paths
        ReadWritePaths = [
          cfg.home
          cfg.appDir
          cfg.cacheDir
          cfg.dataDir
          cfg.tempDir
          cfg.mountsDir
        ] ++ lib.optional cfg.ssl.enable cfg.ssl.dir;

        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        TimeoutStartSec = "5min";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.home}                          0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.appDir}                        0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.cacheDir}                      0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}                       0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.tempDir}                       0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.mountsDir}                     0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.home}/.config                  0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.home}/.config/xo-server        0750 ${cfg.user} ${cfg.group} - -"
    ] ++ lib.optionals cfg.ssl.enable [
      "d ${cfg.ssl.dir}                       0750 ${cfg.user} ${cfg.group} - -"
    ];
  };
}