{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types mkDefault;
  cfg = config.xoa.xo;

  node = pkgs.nodejs_20;         # Upstream recommends latest LTS; Node 20 works well. :contentReference[oaicite:1]{index=1}
  yarn = pkgs.yarn;              # Use nixpkgs Yarn (no corepack writes into /nix/store)
  rsync = pkgs.rsync;
  openssl = pkgs.openssl;

  src = pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo  = "xen-orchestra";
    rev   = cfg.srcRev;          # e.g. "2dd451a7d933f27e550fac673029d8ab79aba70d"
    hash  = cfg.srcHash;         # e.g. "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  };

  # Build script: copy sources into a writable tree, then yarn install/build.
  buildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022

    install -d -m0750 -o ${cfg.user} -g ${cfg.group} "${cfg.appDir}" "${cfg.cacheDir}"

    # Copy sources from the Nix store into the writable app dir
    ${rsync}/bin/rsync -a --delete --exclude 'node_modules/' "${src}/" "${cfg.appDir}/"

    cd "${cfg.appDir}"

    export HOME="${cfg.home}"
    export XDG_CACHE_HOME="${cfg.cacheDir}"
    export YARN_CACHE_FOLDER="${cfg.cacheDir}"
    export NPM_CONFIG_CACHE="${cfg.cacheDir}/npm"
    export PATH="${lib.makeBinPath [ yarn node pkgs.git pkgs.gnumake pkgs.python3 pkgs.pkg-config pkgs.gcc pkgs.libpng pkgs.zlib ]}:$PATH"

    # No 'corepack enable' here — Nix store is read-only.
    ${yarn}/bin/yarn install --frozen-lockfile
    ${yarn}/bin/yarn build
  '';

  # Start script: run xo-server with HTTPS + TOML.
  startScript = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    cd "${cfg.appDir}"
    export NODE_ENV=production
    exec ${node}/bin/node ./packages/xo-server/dist/cli.mjs --config "${cfg.configPath}"
  '';

  # Generate self-signed certs on first run, if missing
  genCerts = pkgs.writeShellScript "xoa-gen-cert.sh" ''
    set -euxo pipefail
    umask 077
    install -d -m0750 "${cfg.ssl.dir}"
    if [ ! -s "${cfg.ssl.key}" ] || [ ! -s "${cfg.ssl.cert}" ]; then
      ${openssl}/bin/openssl req -x509 -newkey rsa:4096 -sha256 -days 825 \
        -keyout "${cfg.ssl.key}" -out "${cfg.ssl.cert}" -nodes \
        -subj "/CN=${cfg.hostname}"
      chmod 0600 "${cfg.ssl.key}"
      chmod 0644 "${cfg.ssl.cert}"
      chown ${cfg.user}:${cfg.group} "${cfg.ssl.key}" "${cfg.ssl.cert}" || true
    fi
  '';
in
{
  options.xoa.xo = {
    enable = mkEnableOption "Build & run Xen Orchestra (XO) Community Edition from source";

    # who/where
    user  = mkOption { type = types.str; default = "xo";   description = lib.mkDefault "Xen Orchestra runtime user"; };
    group = mkOption { type = types.str; default = "xo";   description = "Runtime group for XO."; };
    home  = mkOption { type = types.path; default = "/var/lib/xo"; description = "Home for the xo user."; };

    appDir   = mkOption { type = types.path; default = "/var/lib/xo/app";        description = "Writable app directory."; };
    cacheDir = mkOption { type = types.path; default = "/var/lib/xo/yarn-cache"; description = "Yarn/npm cache directory."; };

    # sources
    srcRev  = mkOption { type = types.str; example = "2dd451a7d933f27e550fac673029d8ab79aba70d"; description = "Git commit or tag to build."; };
    srcHash = mkOption { type = types.str; description = "sha256-TpXyd7DohHG50HvxzfNmWVtiW7BhGSxWk+3lgFMMf/M="; };

    # server config
    configPath = mkOption { type = types.path; default = "/etc/xo-server/config.toml"; description = "XO server TOML path."; };
    host       = mkOption { type = types.str;  default = "0.0.0.0"; description = "XO listen address."; };
    port       = mkOption { type = types.port; default = 443;        description = "XO HTTPS port."; };
    redisUrl   = mkOption { type = types.str;  default = "redis://127.0.0.1:6379/0"; description = "Redis connection URI."; };
    hostname   = mkOption { type = types.str;  default = config.networking.hostName or "xoa"; description = "CN used for self-signed cert."; };

    ssl = {
      enable = mkOption { type = types.bool; default = true; };
      dir    = mkOption { type = types.path; default = "/var/lib/ssl/xo"; };
      key    = mkOption { type = types.path; default = "/var/lib/ssl/xo/key.pem"; };
      cert   = mkOption { type = types.path; default = "/var/lib/ssl/xo/certificate.pem"; };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = cfg.srcRev != "" && cfg.srcHash != "";
        message = "xoa.xo.srcRev and xoa.xo.srcHash must be set."; }
    ];

    # Packages needed for build + remotes (NFS/SMB) and TLS
    environment.systemPackages = with pkgs; [
      node yarn git rsync micro openssl pkg-config python3 gcc gnumake libpng zlib
      nfs-utils cifs-utils
    ];

    # Ensure user/group/home exist (idempotent if you already created them elsewhere)
    users.groups.${cfg.group} = mkDefault { };
    users.users.${cfg.user} = {
      isNormalUser = mkDefault true;
      description = lib.mkDefault "Xen Orchestra runtime user";
      group        = cfg.group;
      home         = cfg.home;
      createHome   = true;
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d ${cfg.home}    0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.appDir}  0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.ssl.dir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    # Minimal XO server TOML; editable as root, XO reloads on restart
    environment.etc."xo-server/config.toml".text = ''
      # Managed by Nix; edit as root and restart xo-server.

      [http.listen]
      hostname = "${cfg.host}"
      port = ${toString cfg.port}

      [http.https]
      enabled = ${if cfg.ssl.enable then "true" else "false"}
      certificate = "${cfg.ssl.cert}"
      key = "${cfg.ssl.key}"

      [redis]
      uri = "${cfg.redisUrl}"
    '';

    # Generate self-signed certs once
    systemd.services.xo-bootstrap = {
      description = "XOA bootstrap (generate HTTPS self-signed certs if missing)";
      wantedBy = [ "multi-user.target" ];
      after    = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = genCerts;
      };
    };

    # Dedicated Redis instance for XO
    services.redis.servers."xo" = {
      enable = true;
      # defaults to port 6379; XO uses DB 0 via cfg.redisUrl
    };

    # Build XO from sources (no corepack)
    systemd.services.xo-build = {
      description = "Build Xen Orchestra (sources pinned via xoa.xo.{srcRev,srcHash})";
      wantedBy = [ "multi-user.target" ];
      after    = [ "network-online.target" "xo-bootstrap.service" ];
      requires = [ "xo-bootstrap.service" ];
      environment = {
        HOME = cfg.home;
        XDG_CACHE_HOME   = cfg.cacheDir;
        YARN_CACHE_FOLDER = cfg.cacheDir;
        NPM_CONFIG_CACHE  = "${cfg.cacheDir}/npm";
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.appDir;
        ExecStart = buildScript;
        ReadWritePaths = [ cfg.appDir cfg.cacheDir ];
        PrivateTmp = true;
      };
    };

    # Allow mounts for NFS/SMB remotes from XO without prompting for password
    security.sudo.extraRules = [{
      users = [ cfg.user ];
      commands = [
        { command = "${pkgs.util-linux}/bin/mount";      options = [ "NOPASSWD" ]; }
        { command = "${pkgs.util-linux}/bin/umount";     options = [ "NOPASSWD" ]; }
        { command = "${pkgs.cifs-utils}/bin/mount.cifs"; options = [ "NOPASSWD" ]; }
        { command = "${pkgs.nfs-utils}/bin/mount.nfs";   options = [ "NOPASSWD" ]; }
      ];
    }];

    # Run XO server AFTER a successful build (and Redis)
    systemd.services.xo-server = {
      description = "Xen Orchestra (xo-server)";
      wantedBy = [ "multi-user.target" ];
      after    = [ "network-online.target" "redis-xo.service" "xo-build.service" ];
      requires = [ "redis-xo.service" "xo-build.service" ];

      environment = { NODE_ENV = "production"; };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.appDir;
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = 3;

        # Don’t start until compiled artifacts exist
        ConditionPathExists = "${cfg.appDir}/packages/xo-server/dist/cli.mjs";

        # Allow writing TLS and cache dirs at runtime
        ReadWritePaths = [ cfg.appDir cfg.cacheDir cfg.ssl.dir ];
      };
    };
  };
}
