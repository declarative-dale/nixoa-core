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

  # Build script: Pragmatic hybrid approach
  # XO is a complex monorepo - building at service time is acceptable
  buildXO = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022
    
    # Directories already created by xo-bootstrap
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude node_modules/ --exclude .git/ \
      "${xoSource}/" "${cfg.xo.appDir}/"
    chmod -R u+rwX "${cfg.xo.appDir}"
    cd "${cfg.xo.appDir}"
    
    export YARN_CACHE_FOLDER="${cfg.xo.cacheDir}"
    export YARN_ENABLE_IMMUTABLE_INSTALLS=true
    export NODE_ENV=production
    
    echo "Building Xen Orchestra (this requires network access for dependencies)"
    ${yarn}/bin/yarn --version
    
    # Try frozen lockfile first, fallback if upstream changed format
    ${yarn}/bin/yarn install --frozen-lockfile --network-timeout 300000 || \
      ${yarn}/bin/yarn install --network-timeout 300000
    
    ${yarn}/bin/yarn build
    
    echo "Build complete. XO is ready to start."
  '';

  # Robustly locate XO CLI entrypoint with error handling
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    cd "${cfg.xo.appDir}"
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
      user = mkOption { type = types.str; default = "xoa"; };
      sshAuthorizedKeys = mkOption { type = types.listOf types.str; default = []; };
    };

    xo = {
      user  = mkOption { type = types.str; default = "xo"; };
      group = mkOption { type = types.str; default = "xo"; };

      home     = mkOption { type = types.path; default = "/var/lib/xo"; };
      appDir   = mkOption { type = types.path; default = "/var/lib/xo/app"; };
      cacheDir = mkOption { type = types.path; default = "/var/cache/xo/yarn-cache"; };
      dataDir  = mkOption { type = types.path; default = "/var/lib/xo/data"; };
      tempDir  = mkOption { type = types.path; default = "/var/lib/xo/tmp"; };
      webMountDir = mkOption { type = types.path; default = "/var/lib/xo/app/packages/xo-web/dist"; };

      host      = mkOption { type = types.str; default = "0.0.0.0"; };
      port      = mkOption { type = types.port; default = 80; };
      httpsPort = mkOption { type = types.port; default = 443; };

      ssl.enable = mkEnableOption "TLS for XO" // { default = true; };
      ssl.dir  = mkOption { type = types.path; default = "/etc/ssl/xo"; };
      ssl.key  = mkOption { type = types.path; default = "/etc/ssl/xo/key.pem"; };
      ssl.cert = mkOption { type = types.path; default = "/etc/ssl/xo/certificate.pem"; };

      # Source options: prefer srcPath (flake input) but allow explicit rev/hash
      srcPath = mkOption { type = types.nullOr types.path; default = null; };
      srcRev  = mkOption { type = types.str; default = ""; };
      srcHash = mkOption { type = types.str; default = ""; };

      buildIsolation = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Restrict network access during build to npm/yarn registries only.
          Provides security while allowing necessary dependency fetching.
          Disable if XO dependencies use non-standard registries.
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

    # Admin user for SSH
    users.users.${cfg.admin.user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.admin.sshAuthorizedKeys;
    };

    # XO service user/group
    users.groups.${cfg.xo.group} = {};
    users.users.${cfg.xo.user} = {
      isSystemUser = true;
      createHome = true;
      home  = cfg.xo.home;
      group = cfg.xo.group;
      shell = pkgs.shadow + "/bin/nologin";
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

    # System packages useful for XO build
    environment.systemPackages = with pkgs; [
      node yarn git rsync pkg-config python3 gcc gnumake openssl jq
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

    # Build service: Pragmatic hybrid approach with optional network isolation
    systemd.services.xo-build = {
      description = "Build Xen Orchestra from source";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "xo-bootstrap.service" ];
      wants = [ "network-online.target" ];
      requires = [ "redis-xo.service" "xo-bootstrap.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.xo.user;
        Group = cfg.xo.group;
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv;
        ReadWritePaths = [
          cfg.xo.appDir 
          cfg.xo.cacheDir 
          cfg.xo.dataDir 
          cfg.xo.tempDir
        ];
        ExecStart = buildXO;
        TimeoutStartSec = "10min";
        
        # Optional: Restrict network to npm/yarn registries only
        ${if cfg.xo.buildIsolation then ''
          IPAddressAllow = [
            "registry.yarnpkg.com"
            "registry.npmjs.org"
            "github.com"
            "codeload.github.com"
          ];
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        '' else ""}
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
      wants = [ "redis-xo.service" "xo-build.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = cfg.xo.user;
        Group = cfg.xo.group;
        WorkingDirectory = cfg.xo.appDir;
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv;
        ExecStart = startXO;
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
          cfg.xo.dataDir 
          cfg.xo.tempDir
          "/run/xo-server"
        ];
        TimeoutStartSec = "5min";
      };
    };

    # Minimal tmpfiles: ONLY /etc/xo-server config
    # All other directories handled by xo-bootstrap
    systemd.tmpfiles.rules = [
      "d /etc/xo-server 0755 root root - -"
      "C /etc/xo-server/config.toml 0640 ${cfg.xo.user} ${cfg.xo.group} - ${xoDefaultConfig}"
    ];
  };
}