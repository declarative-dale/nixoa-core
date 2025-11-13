{ config, lib, pkgs, xoSrc ? null, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.xoa;

  node   = pkgs.nodejs_20;
  yarn   = pkgs.yarn;
  rsync  = pkgs.rsync;
  openssl = pkgs.openssl;
  # NEW: default xo-server config, copied once if missing
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
  # cert generation (self-signed), guarded by cfg.xo.ssl.enable
  genCerts = pkgs.writeShellScript "xo-gen-certs.sh" ''
    set -euo pipefail
    umask 077
    install -d -m 0750 -o ${cfg.xo.user} -g ${cfg.xo.group} "${cfg.xo.ssl.dir}"

    if [ ! -s "${cfg.xo.ssl.key}" ] || [ ! -s "${cfg.xo.ssl.cert}" ]; then
      ${openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
        -keyout "${cfg.xo.ssl.key}" -out "${cfg.xo.ssl.cert}" \
        -subj "/CN=${config.networking.hostName}" -addext "subjectAltName=DNS:${config.networking.hostName}"
      chown ${cfg.xo.user}:${cfg.xo.group} "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}"
      chmod 0640 "${cfg.xo.ssl.key}" "${cfg.xo.ssl.cert}"
    fi
  '';

  # rsync source → appDir and run Yarn build once at boot
  buildXO = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022

    install -d -m0750 -o ${cfg.xo.user} -g ${cfg.xo.group} "${cfg.xo.appDir}" "${cfg.xo.cacheDir}"
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude node_modules/ --exclude .git/ \
      "${xoSource}/" "${cfg.xo.appDir}/"
    chmod -R u+rwX "${cfg.xo.appDir}"
    cd "${cfg.xo.appDir}"

    export YARN_CACHE_FOLDER="${cfg.xo.cacheDir}"
    export YARN_ENABLE_IMMUTABLE_INSTALLS=true
    export NODE_ENV=production

    ${yarn}/bin/yarn --version
    # try frozen first, then non-frozen if upstream changed lockfile format
    ${yarn}/bin/yarn install --frozen-lockfile --network-timeout 300000 || \
      ${yarn}/bin/yarn install --network-timeout 300000

    ${yarn}/bin/yarn build
    chown -R ${cfg.xo.user}:${cfg.xo.group} "${cfg.xo.appDir}"
  '';

  # robustly locate XO CLI entrypoint
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    cd "${cfg.xo.appDir}"
    CLI=""
    if [ -f packages/xo-server/dist/cli.mjs ]; then
      CLI="packages/xo-server/dist/cli.mjs"
    elif [ -f packages/xo-server/dist/cli.js ]; then
      CLI="packages/xo-server/dist/cli.js"
    else
      CLI=$(find packages/xo-server/dist -name "cli.mjs" -o -name "cli.js" | head -1)
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

    # system packages useful for XO build
    environment.systemPackages = with pkgs; [
      node yarn git rsync pkg-config python3 gcc gnumake openssl jq
    ];

    # Directories via systemd native dirs + tmpfiles
    systemd.services.xo-build = {
      description = "Build Xen Orchestra from source";
      wantedBy = [ "multi-user.target" ];
      after    = [ "network-online.target" ];
      requires = [ "redis-xo.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.xo.user;
        Group = cfg.xo.group;
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.xo.extraServerEnv;
        ReadWritePaths = [
          cfg.xo.appDir cfg.xo.cacheDir cfg.xo.dataDir cfg.xo.tempDir
        ] ++ lib.optional cfg.xo.ssl.enable cfg.xo.ssl.dir;
        ExecStart = buildXO;
        TimeoutStartSec = "10min";
      };
    };

    systemd.services.xo-bootstrap = mkIf cfg.xo.ssl.enable {
      description = "XO TLS certificate generation";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.xo.user;
        Group = cfg.xo.group;
        ReadWritePaths = [ cfg.xo.ssl.dir ];
        ExecStart = genCerts;
      };
    };

    systemd.services.xo-server = {
      description = "Xen Orchestra (xo-server)";
      after = [ "systemd-tmpfiles-setup.service" "network-online.target" "redis-xo.service" "xo-build.service" ]
        ++ lib.optional cfg.xo.ssl.enable "xo-bootstrap.service";
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
        StateDirectory = [ "xo" ];
        CacheDirectory = [ "xo" ];
        RuntimeDirectory = [ "xo" ];
        ReadOnlyPaths = [ "/etc/xo-server/config.toml" ];
        ReadWritePaths = [ cfg.xo.dataDir cfg.xo.tempDir ];
        TimeoutStartSec = "5min";
      };
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d /etc/xo-server 0755 root root - -"
      "C /etc/xo-server/config.toml 0640 ${cfg.xo.user} ${cfg.xo.group} - ${xoDefaultConfig}"
     ]
     ++[
      "d ${cfg.xo.home}                   0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.appDir}                 0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.cacheDir}               0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.dataDir}                0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.tempDir}                0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.home}/.config           0750 ${cfg.xo.user} ${cfg.xo.group} - -"
      "d ${cfg.xo.home}/.config/xo-server 0750 ${cfg.xo.user} ${cfg.xo.group} - -"
     ] ++ lib.optionals cfg.xo.ssl.enable [
      "d ${cfg.xo.ssl.dir}                0750 ${cfg.xo.user} ${cfg.xo.group} - -"
    ];
  };
}
