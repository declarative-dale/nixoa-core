{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.xoa.xo;

  # Toolchain & tools
  node   = pkgs.nodejs_20;     # Latest LTS generally recommended by Vates
  yarn   = pkgs.yarn;          # Yarn classic from nixpkgs
  rsync  = pkgs.rsync;

    # XO sources: prefer a flake-provided/local path (cfg.srcPath), otherwise fetch by rev/hash
    xoSrc =
      if cfg.srcPath != null then cfg.srcPath else
        pkgs.fetchFromGitHub {
          owner = "vatesfr";
          repo  = "xen-orchestra";
          rev   = cfg.srcRev;
          hash  = cfg.srcHash;
        };

  # Where XO's "home" lives (parent of appDir)
  xoHome = builtins.dirOf cfg.appDir;

  # Build script: copy sources into writable appDir, install deps & build
  buildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euo pipefail

    # Ensure directories exist with sane perms for the xo user
    install -d -m 0750 -o ${cfg.user} -g ${cfg.group} "${cfg.appDir}" "${cfg.cacheDir}"

    # Copy from read-only Nix store to a writable working tree.
    # DO NOT preserve perms from the store (0444/0555) -> make them writable.
    ${rsync}/bin/rsync -a --no-perms --chmod=ugo=rwX --delete \
      --exclude 'node_modules/' \
      "${xoSrc}/" "${cfg.appDir}/"

    # Double-check write perms (belt & suspenders)
    chmod -R u+rwX "${cfg.appDir}"
    chown -R ${cfg.user}:${cfg.group} "${cfg.appDir}" "${cfg.cacheDir}"

    export HOME="${xoHome}"
    export XDG_CACHE_HOME="$(dirname "${cfg.cacheDir}")"
    export YARN_CACHE_FOLDER="${cfg.cacheDir}"
    export NPM_CONFIG_CACHE="${cfg.cacheDir}/npm"
    export npm_config_nodedir="${node}/include/node"
    export PYTHON="${pkgs.python3}/bin/python3"
    export PKG_CONFIG_PATH="${lib.makeSearchPath "lib/pkgconfig" [ pkgs.fuse.dev pkgs.fuse3.dev ]}"
    export CFLAGS="-I${pkgs.fuse.dev}/include -I${pkgs.fuse3.dev}/include ''${CFLAGS:-}"
    export LDFLAGS="-L${pkgs.fuse.out}/lib -L${pkgs.fuse3.out}/lib ''${LDFLAGS:-}"
    export PATH="${lib.makeBinPath [ yarn node pkgs.gnumake pkgs.gcc pkgs.pkg-config pkgs.git pkgs.libtool pkgs.autoconf pkgs.automake ]}:$PATH"

    cd "${cfg.appDir}"

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
   srcPath = mkOption {
     type = types.nullOr types.path;
     default = null;
     description = ''
        If set, use this path as the Xen Orchestra sources (e.g. a flake input
        pinned in flake.lock or a local checkout). When non-null, srcRev/srcHash are ignored.
        '';
      };

    user = mkOption {
      type = types.str;
      default = "xo";
      description = "System user running XO build/server.";
    };
    group = mkOption {
      type = types.str;
      default = "xo";
      description = "Primary group for XO user.";
    };

    appDir = mkOption {
      type = types.path;
      default = "/var/lib/xo/app";
      description = "Writable working tree where sources are copied and built.";
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/cache/xo/yarn-cache";
      description = "Yarn/NPM cache directory.";
    };

    ssl = {
      enable = mkEnableOption "Enable TLS assets directory management for xo-server" // { default = false; };
      dir = mkOption {
        type = types.path;
        default = "/var/lib/xo/tls";
        description = "Directory containing TLS cert/key for xo-server (if used via xo-server config).";
      };
    };

    # Extra env for xo-server (merged into service)
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

    # Build: compile the monorepo with yarn/node-gyp toolchain available
    systemd.services.xo-build = {
      description = "Build Xen Orchestra (sources pinned via xoa.xo.{srcRev,srcHash})";
      wantedBy = [ "multi-user.target" ];
      wants    = [ "network-online.target" ];
      after    = [ "network-online.target" ];

      # Put build tools on PATH for the unit
      path = with pkgs; [
        nodejs_20 yarn gnumake gcc python3 pkg-config git
        fuse fuse3 libtool autoconf automake
      ];

      environment = {
        HOME = xoHome;
        XDG_CACHE_HOME   = builtins.dirOf cfg.cacheDir;
        YARN_CACHE_FOLDER = cfg.cacheDir;
        NPM_CONFIG_CACHE  = "${cfg.cacheDir}/npm";
        npm_config_nodedir = "${node}/include/node";
        PYTHON = "${pkgs.python3}/bin/python3";
        PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [ pkgs.fuse.dev pkgs.fuse3.dev ];
        CFLAGS  = "-I${pkgs.fuse.dev}/include -I${pkgs.fuse3.dev}/include";
        LDFLAGS = "-L${pkgs.fuse.out}/lib -L${pkgs.fuse3.out}/lib";
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
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
