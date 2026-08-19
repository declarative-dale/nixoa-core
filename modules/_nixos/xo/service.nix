# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixoa.xo;
  inherit (lib) attrByPath mkIf optionalAttrs optionals;
  valkeyCompat =
    if pkgs ? valkey-compat-redis
    then pkgs.valkey-compat-redis
    else if pkgs ? valkey-compat
    then pkgs.valkey-compat
    else pkgs.valkey;
  storageEnabled = cfg.storage.enableNFS || cfg.storage.enableCIFS || cfg.storage.enableVHD;
  xoConfig =
    if cfg.config.file == null
    then {}
    else builtins.fromTOML (builtins.readFile cfg.config.file);
  configValue = path: attrByPath path null xoConfig;
  expectedListeners =
    [{port = 80;}]
    ++ optionals cfg.tls.enable [
      {
        port = 443;
        cert = cfg.tls.cert;
        key = cfg.tls.key;
      }
    ];
  expectedMounts = {
    "/" = "${cfg.home}/xen-orchestra/@xen-orchestra/web/dist";
    "/v5" = "${cfg.home}/xen-orchestra/packages/xo-web/dist";
    "/v6" = "${cfg.home}/xen-orchestra/@xen-orchestra/web/dist";
  };
  startXO = pkgs.writeShellScript "xo-start" ''
    set -euo pipefail
    export HOME=${lib.escapeShellArg cfg.home}
    export NODE_ENV=production
    exec ${cfg.package}/bin/xo-server "$@"
  '';
in {
  config = mkIf cfg.enable {
    users.groups.${cfg.group} = {};
    users.groups.fuse = {};
    users.users.${cfg.user} = {
      isSystemUser = true;
      description = "Xen Orchestra service account";
      createHome = true;
      group = cfg.group;
      home = cfg.home;
      shell = "${pkgs.shadow}/bin/nologin";
      extraGroups = ["fuse"];
    };

    services.redis = {
      package = pkgs.valkey;
      servers.xo = {
        enable = true;
        user = cfg.user;
        unixSocket = "/run/redis-xo/redis.sock";
        unixSocketPerm = 770;
        settings =
          {
            port = 0;
            databases = 16;
            maxmemory-policy = cfg.redis.maxmemoryPolicy;
          }
          // optionalAttrs (cfg.redis.maxmemory != null) {
            maxmemory = cfg.redis.maxmemory;
          };
      };
    };

    environment.etc = mkIf (cfg.config.file != null) {
      "xo-server/config.nixoa.toml" = {
        source = cfg.config.file;
        mode = "0644";
      };
    };

    environment.systemPackages =
      [
        valkeyCompat
        pkgs.rsync
        pkgs.openssl
        pkgs.fuse
        pkgs.lvm2
        pkgs.libguestfs
        pkgs.ntfs3g
        pkgs.git
        pkgs.valkey
      ]
      ++ optionals cfg.storage.enableNFS [pkgs.nfs-utils]
      ++ optionals cfg.storage.enableCIFS [pkgs.cifs-utils];

    systemd.tmpfiles.rules = [
      "d ${cfg.home} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.tempDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.home}/.config 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.home}/.config/xo-server 0750 ${cfg.user} ${cfg.group} - -"
      "d /etc/xo-server 0755 root root - -"
      "d /var/lib/xo-server 0750 ${cfg.user} ${cfg.group} - -"
      "L+ ${cfg.home}/xen-orchestra - - - - ${cfg.package}/libexec/xen-orchestra"
    ];

    security.pam.loginLimits = [
      {
        domain = cfg.user;
        type = "soft";
        item = "nofile";
        value = "65536";
      }
      {
        domain = cfg.user;
        type = "hard";
        item = "nofile";
        value = "1048576";
      }
    ];

    systemd.services.xo-server = {
      description = "Xen Orchestra Server";
      after =
        [
          "systemd-tmpfiles-setup.service"
          "network-online.target"
          "redis-xo.service"
        ]
        ++ lib.optional (cfg.tls.enable && cfg.tls.autoCert) "xo-autocert.service";
      wants = [
        "network-online.target"
        "redis-xo.service"
      ];
      wantedBy = ["multi-user.target"];
      requires = ["redis-xo.service"];

      path =
        optionals (config.nixoa.xo.internal.sudoWrapper != null) [config.nixoa.xo.internal.sudoWrapper]
        ++ [
          pkgs.util-linux
          pkgs.git
          pkgs.openssl
          pkgs.lvm2
          pkgs.coreutils
          pkgs.xen
        ]
        ++ optionals cfg.storage.enableNFS [pkgs.nfs-utils]
        ++ optionals cfg.storage.enableCIFS [pkgs.cifs-utils];

      environment =
        cfg.extraServerEnv
        // {
          HOME = cfg.home;
          XDG_CONFIG_HOME = "${cfg.home}/.config";
          XDG_CACHE_HOME = cfg.cacheDir;
          NODE_ENV = "production";
          LD_LIBRARY_PATH = lib.makeLibraryPath [
            pkgs.fuse
            pkgs.libguestfs
            pkgs.stdenv.cc.cc.lib
          ];
        };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/libexec/xen-orchestra";
        StateDirectory = "xo";
        CacheDirectory = "xo";
        LogsDirectory = "xo";
        RuntimeDirectory = "xo xo-server";
        ExecStart = startXO;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5min";
        PrivateTmp = true;
        ProtectSystem = "full";
        ProtectHome = true;
        PrivateDevices = false;
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        CapabilityBoundingSet =
          ["CAP_NET_BIND_SERVICE"]
          ++ optionals storageEnabled [
            "CAP_SETUID"
            "CAP_SETGID"
            "CAP_SETPCAP"
            "CAP_SYS_ADMIN"
            "CAP_DAC_READ_SEARCH"
            "CAP_DAC_OVERRIDE"
          ];
        ReadOnlyPaths =
          ["/etc/xo-server/config.nixoa.toml"]
          ++ optionals cfg.tls.enable [cfg.tls.dir];
        ReadWritePaths =
          [
            cfg.home
            cfg.cacheDir
            cfg.dataDir
            cfg.tempDir
            "/var/lib/xo-server"
            "/var/log/xo"
            "/run/lock"
            "/run/redis-xo"
          ]
          ++ optionals storageEnabled [cfg.storage.mountsDir];
        LimitNOFILE = "1048576";
      };
    };

    assertions = [
      {
        assertion = cfg.package != null;
        message = "nixoa.xo.package must be configured.";
      }
      {
        assertion = cfg.config.file != null;
        message = "nixoa.xo.config.file must provide the NiXOA xo-server TOML system override.";
      }
      {
        assertion = configValue ["redis" "socket"] == "/run/redis-xo/redis.sock";
        message = "nixoa.xo.config.file must use the managed Redis socket.";
      }
      {
        assertion = configValue ["dataStore" "path"] == cfg.dataDir;
        message = "nixoa.xo.config.file dataStore.path must match nixoa.xo.dataDir.";
      }
      {
        assertion = configValue ["tempDir" "path"] == cfg.tempDir;
        message = "nixoa.xo.config.file tempDir.path must match nixoa.xo.tempDir.";
      }
      {
        assertion = configValue ["http" "redirectToHttps"] == cfg.tls.enable;
        message = "nixoa.xo.config.file http.redirectToHttps must match nixoa.xo.tls.enable.";
      }
      {
        assertion = configValue ["http" "listen"] == expectedListeners;
        message = "nixoa.xo.config.file HTTP listeners must match the managed TLS policy.";
      }
      {
        assertion = configValue ["http" "mounts"] == expectedMounts;
        message = "nixoa.xo.config.file HTTP mounts must match nixoa.xo.home.";
      }
      {
        assertion = configValue ["remoteOptions" "useSudo"] == true;
        message = "nixoa.xo.config.file remoteOptions.useSudo must remain enabled.";
      }
      {
        assertion = configValue ["remoteOptions" "mountsDir"] == cfg.storage.mountsDir;
        message = "nixoa.xo.config.file remoteOptions.mountsDir must match nixoa.xo.storage.mountsDir.";
      }
    ];
  };

  options.nixoa.xo.internal.sudoWrapper = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    internal = true;
  };
}
