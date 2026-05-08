# SPDX-License-Identifier: Apache-2.0
# XO systemd service
{
  config,
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) mkIf optional optionals;
  cfg = config.nixoa.xo;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;

  startScript = config.nixoa.xo.internal.startScript;
in {
  config = mkIf context.enableXO {
    systemd.services.xo-server = {
      description = "Xen Orchestra Server";
      after =
        [
          "systemd-tmpfiles-setup.service"
          "network-online.target"
          "redis-xo.service"
        ]
        ++ lib.optional context.enableAutoCert "xo-autocert.service";

      wants = [
        "network-online.target"
        "redis-xo.service"
      ];
      wantedBy = ["multi-user.target"];
      requires = ["redis-xo.service"];

      # Sudo wrapper must be first in path to intercept sudo calls
      # (defined in storage/wrapper-script.nix via nixoa.xo.internal.sudoWrapper)
      path =
        optional (config.nixoa.xo.internal.sudoWrapper != null) config.nixoa.xo.internal.sudoWrapper
        ++ (with pkgs; [
          util-linux
          git
          openssl
          lvm2
          coreutils
          xen
        ])
        ++ optionals context.enableNFS [pkgs.nfs-utils]
        ++ optionals context.enableCIFS [pkgs.cifs-utils];

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

        ExecStart = "${startScript}";

        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5min";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "full";
        ProtectHome = true;
        PrivateDevices = false;

        # XO binds public 80/443 directly. Broader mount-related privileges are
        # only available to root children reached through sudo's validated helper.
        AmbientCapabilities = [
          "CAP_NET_BIND_SERVICE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_BIND_SERVICE"
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_SETPCAP"
          "CAP_SYS_ADMIN"
          "CAP_DAC_READ_SEARCH"
          "CAP_DAC_OVERRIDE"
        ];

        ReadOnlyPaths =
          ["/etc/xo-server/config.nixoa.toml"]
          ++ lib.optionals context.enableTLS [cfg.tls.dir];

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
          ++ lib.optionals storageEnabled [context.mountsDir];

        LimitNOFILE = "1048576";
      };
    };
  };
}
