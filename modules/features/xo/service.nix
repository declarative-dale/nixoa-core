# SPDX-License-Identifier: Apache-2.0
# XO Server systemd service, Redis backend, and start script
{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;

  # Reference the configured package
  xoaPackage = pkgs.nixoa.xen-orchestra-ce;

  # XO app directory is immutable in /nix/store
  xoAppDir = "${xoaPackage}/libexec/xen-orchestra";

  # Get XO service user/group from vars
  xoUser = vars.xoUser;
  xoGroup = vars.xoGroup;

  # Start script for xo-server
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${cfg.home}"
    export NODE_ENV="production"
    exec ${pkgs.nodejs_24}/bin/node "${xoAppDir}/packages/xo-server/dist/cli.mjs" "$@"
  '';
in
{
  config = mkIf vars.enableXO {
    assertions = [
      {
        assertion = cfg.home != null;
        message = "XO home directory must be configured";
      }
    ];

    # Valkey service for XO (drop-in Redis replacement)
    services.redis.package = pkgs.valkey;
    services.redis.servers.xo = {
      enable = true;
      user = xoUser;
      unixSocket = "/run/redis-xo/redis.sock";
      unixSocketPerm = 770;
      settings = {
        port = 0;
        databases = 16;
        maxmemory = "256mb";
        maxmemory-policy = "allkeys-lru";
      };
    };

    # System packages needed by XO (runtime only)
    environment.systemPackages = with pkgs; [
      rsync
      openssl
      fuse
      fuse3
      lvm2
      libguestfs
      ntfs3g
    ];

    # XO Server service
    systemd.services.xo-server = {
      description = "Xen Orchestra Server";
      after =
        [
          "systemd-tmpfiles-setup.service"
          "network-online.target"
          "redis-xo.service"
        ]
        ++ lib.optional vars.enableAutoCert "xo-autocert.service";

      wants = [
        "network-online.target"
        "redis-xo.service"
      ];
      wantedBy = [ "multi-user.target" ];
      requires = [ "redis-xo.service" ];

      # Sudo wrapper must be first in path to intercept sudo calls
      # (defined in storage.nix via nixoa.xo.internal.sudoWrapper)
      path =
        lib.optional (config.nixoa.xo.internal.sudoWrapper != null) config.nixoa.xo.internal.sudoWrapper
        ++ (with pkgs; [
          nodejs_24
          util-linux
          git
          openssl
          lvm2
          coreutils
          nfs-utils
          cifs-utils
          xen
        ]);

      # Environment for xo-server
      environment = cfg.extraServerEnv // {
        HOME = cfg.home;
        XDG_CONFIG_HOME = "${cfg.home}/.config";
        XDG_CACHE_HOME = cfg.cacheDir;
        NODE_ENV = "production";
        LD_LIBRARY_PATH = lib.makeLibraryPath [
          pkgs.fuse3
          pkgs.fuse
          pkgs.libguestfs
          pkgs.stdenv.cc.cc.lib
        ];
      };

      serviceConfig = {
        User = xoUser;
        Group = xoGroup;

        WorkingDirectory = xoAppDir;
        StateDirectory = "xo";
        CacheDirectory = "xo";
        LogsDirectory = "xo";
        RuntimeDirectory = "xo xo-server";

        ExecStart = "${startXO}";

        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5min";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "full";
        ProtectHome = true;
        PrivateDevices = false;

        # Capabilities for HTTP/HTTPS ports and sudo operations
        AmbientCapabilities = [
          "CAP_NET_BIND_SERVICE"
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_SETPCAP"
          "CAP_SYS_ADMIN"
          "CAP_DAC_OVERRIDE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_BIND_SERVICE"
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_SETPCAP"
          "CAP_SYS_ADMIN"
          "CAP_DAC_OVERRIDE"
        ];

        ReadOnlyPaths = lib.optionals vars.enableTLS [ cfg.tls.dir ];

        ReadWritePaths = [
          cfg.home
          cfg.cacheDir
          cfg.dataDir
          cfg.tempDir
          "/etc/xo-server"
          "/var/lib/xo-server"
          vars.mountsDir
          "/run/lock"
          "/run/redis-xo"
          "/dev"
          "/sys"
          "/var/log"
        ];

        LimitNOFILE = "1048576";
      };
    };

    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d ${cfg.home}                          0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.cacheDir}                      0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.dataDir}                       0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.tempDir}                       0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.home}/.config                  0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.home}/.config/xo-server        0750 ${xoUser} ${xoGroup} - -"
      "d /etc/xo-server                       0755 root root - -"
      "d /var/lib/xo-server                   0750 ${xoUser} ${xoGroup} - -"
      "L+ ${cfg.home}/xen-orchestra           -    -        -        - ${cfg.package}/libexec/xen-orchestra"
    ];
  };
}
