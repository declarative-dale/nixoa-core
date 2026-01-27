# SPDX-License-Identifier: Apache-2.0
# XO systemd service
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

  xoaPackage = cfg.package;
  xoAppDir = "${xoaPackage}/libexec/xen-orchestra";
  xoUser = vars.xoUser;
  xoGroup = vars.xoGroup;

  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${cfg.home}"
    export NODE_ENV="production"
    exec ${pkgs.nodejs_24}/bin/node "${xoAppDir}/packages/xo-server/dist/cli.mjs" "$@"
  '';
in
{
  config = mkIf vars.enableXO {
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
      # (defined in storage/wrapper.nix via nixoa.xo.internal.sudoWrapper)
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
  };
}
