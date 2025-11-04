{ config, lib, pkgs, xoSrc ? null, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.xoa.xo;

  # If provided via flake specialArgs, use it by default (centralized pinning).
  defaultSrcPath = if xoSrc != null then xoSrc else null;
  # Toolchain & tools
  node   = pkgs.nodejs_20;     # Latest LTS generally recommended by Vates
  yarn   = pkgs.yarn;          # Yarn classic from nixpkgs
  rsync  = pkgs.rsync;
  openssl = pkgs.openssl;

  xoSource = if cfg.srcPath != null then cfg.srcPath else pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo  = "xen-orchestra";
    rev   = cfg.srcRev;
    };

  # Where XO's "home" lives (parent of appDir)
  xoHome = builtins.dirOf cfg.appDir;

  # Build script: copy sources into writable appDir, install deps & build
  buildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euxo pipefail
    umask 022

    # Ensure directories exist with sane perms for the xo user
    install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${cfg.appDir}" "${cfg.cacheDir}"

    # Copy sources but DO NOT preserve read-only perms from /nix/store
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude 'node_modules/' \
      "${xoSource}/" "${cfg.appDir}/"
    # Make sure owner can write everywhere
    chmod -R u+rwX "${cfg.appDir}"

    cd "${cfg.appDir}"
    export HOME="${cfg.home}"
    export XDG_CACHE_HOME="${cfg.cacheDir}"
    export YARN_CACHE_FOLDER="${cfg.cacheDir}"
    export NPM_CONFIG_CACHE="${cfg.cacheDir}/npm"
    export npm_config_nodedir="${node}/include/node"
    export PYTHON="${pkgs.python3}/bin/python3"
    export PKG_CONFIG_PATH="${lib.makeSearchPath "lib/pkgconfig" [ pkgs.fuse.dev pkgs.fuse3.dev ]}"
    export CFLAGS="-I${pkgs.fuse.dev}/include -I${pkgs.fuse3.dev}/include ''${CFLAGS:-}"
    export LDFLAGS="-L${pkgs.fuse.out}/lib -L${pkgs.fuse3.out}/lib ''${LDFLAGS:-}"
    export PATH="${lib.makeBinPath [ yarn node pkgs.gnumake pkgs.gcc pkgs.pkg-config pkgs.git pkgs.libtool pkgs.autoconf pkgs.automake ]}:$PATH"

    # Install & build (no network prompts, deterministic)
    ${yarn}/bin/yarn install --frozen-lockfile --non-interactive
    ${yarn}/bin/yarn build
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
    srcRev  = mkOption {
      type = types.str; default = "";
      description = "Git revision to build (used only when srcPath=null).";
    };
    srcHash = mkOption {
      type = types.str; default = "";
      description = "sha256 for the above revision (used only when srcPath=null).";
    };
    user = mkOption { type = types.str; default = "xo"; };
    group = mkOption { type = types.str; default = "xo"; };
    home  = mkOption { type = types.path; default = "/var/lib/xo"; };
    appDir   = mkOption { type = types.path; default = "/var/lib/xo/app"; };
    # NixOS best practice: put caches under /var/cache
    cacheDir = mkOption { type = types.path; default = "/var/cache/xo/yarn-cache"; };

    ssl = {
      enable = mkEnableOption "Enable TLS assets directory management for xo-server" // { default = true; };
      dir = mkOption {
        type = types.path;
        default = "/etc/ssl/xo";
        description = "Directory containing TLS cert/key for xo-server (if used via xo-server config).";
      };
      key    = mkOption { type = types.path; default = "/etc/ssl/xo/key.pem"; };
      cert   = mkOption { type = types.path; default = "/etc/ssl/xo/certificate.pem"; };
    };

    # Extra env for xo-server (merged into service)
    extraServerEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment variables for xo-server.";
    };
  };
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

  config = mkIf cfg.enable {
    assertions = [
      { assertion = (cfg.srcPath != null) || (cfg.srcRev != "" && cfg.srcHash != "");
        message = "Provide xoa.xo.srcPath OR both xoa.xo.srcRev and xoa.xo.srcHash."; }
    ];
    # Packages for convenience (optional)
    environment.systemPackages = with pkgs; [
      node yarn git rsync micro openssl pkg-config python3 gcc gnumake libpng zlib
      nfs-utils cifs-utils
    ];
    # Node-gyp toolchain & headers for native modules like fuse-native
    systemd.services.xo-build.path = with pkgs; [
     nodejs_20 yarn gnumake gcc python3 pkg-config git fuse fuse3 libtool autoconf automake
    ];
    # Build: compile the monorepo with yarn/node-gyp toolchain available
    systemd.services.xo-build = {
      description = "Build Xen Orchestra (sources pinned via xoa.xo.{srcRev,srcHash})";
      wantedBy = [ "multi-user.target" ];
      wants    = [ "network-online.target" ];
      after    = [ "network-online.target" ];
      environment = {
        HOME = xoHome;
        XDG_CACHE_HOME   = builtins.dirOf cfg.cacheDir;
        YARN_CACHE_FOLDER = cfg.cacheDir;
        NPM_CONFIG_CACHE  = "${cfg.cacheDir}/npm";
        npm_config_nodedir = "${pkgs.nodejs_20}/include/node";
        PYTHON = "${pkgs.python3}/bin/python3";
        PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [ pkgs.fuse.dev pkgs.fuse3.dev ];
        CFLAGS  = "-I${pkgs.fuse.dev}/include -I${pkgs.fuse3.dev}/include";
        LDFLAGS = "-L${pkgs.fuse.out}/lib -L${pkgs.fuse3.out}/lib";
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "oneshot";
        User  = cfg.user;
        Group = cfg.group;

        # Create /var/lib/xo and /var/cache/xo managed by systemd
        StateDirectory       = "xo";
        StateDirectoryMode   = "0750";
        CacheDirectory       = "xo";
        CacheDirectoryMode   = "0750";

        WorkingDirectory = cfg.appDir;

        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${cfg.appDir} ${cfg.cacheDir}"
          "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.appDir} ${cfg.cacheDir}"
          "+${pkgs.coreutils}/bin/chmod -R u+rwX ${cfg.appDir} ${cfg.cacheDir}"
        ];
        ExecStart = buildScript;

        # Open the writable paths even if hardening is enabled elsewhere
        ReadWritePaths = [ cfg.appDir cfg.cacheDir ] ++ lib.optionals cfg.ssl.enable [ cfg.ssl.dir ];

        PrivateTmp = true;
      };
    };

    # Run server after build
    systemd.services.xo-server = {
      description = "Xen Orchestra server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "xo-build.service" ];
      after    = [ "xo-build.service" "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        # Managed dirs; server writes state under /var/lib/xo and caches under /var/cache/xo
        StateDirectory       = "xo";
        StateDirectoryMode   = "0750";
        CacheDirectory       = "xo";
        CacheDirectoryMode   = "0750";

        WorkingDirectory = cfg.appDir;
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = 3;

        # Don’t start until compiled artifacts exist
        ConditionPathExists = "${cfg.appDir}/packages/xo-server/dist/cli.mjs";

        # Allow writing TLS and cache dirs at runtime
        ReadWritePaths = [ cfg.appDir cfg.cacheDir ] ++ lib.optionals cfg.ssl.enable [ cfg.ssl.dir ];

        PrivateTmp = true;
      };

      environment = cfg.extraServerEnv // {
        HOME = xoHome;
        NODE_ENV = "production";
      };
    };

    # Optionally ensure TLS dir exists (if enabled)
    systemd.tmpfiles.rules = lib.mkIf cfg.ssl.enable [
      "d ${cfg.ssl.dir} 0750 ${cfg.user} ${cfg.group} - -"
    ];
  };
}
