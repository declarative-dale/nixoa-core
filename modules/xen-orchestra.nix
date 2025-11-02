{ config, lib, pkgs, ... }:
#######################################
## Xen Orchestra module options
#######################################
xoa.xo = {
  enable = true;
  user     = "xo";
  srcRev   = "2dd451a7d933f27e550fac673029d8ab79aba70d";   # commit pin
  # IMPORTANT: update after the first build fails with:
  #   got: sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXX
  # Paste that value here and rebuild.
  srcHash  = "sha256-TpXyd7DohHG50HvxzfNmWVtiW7BhGSxWk+3lgFMMf/M=";        # SRI hash for that commit
  tls.commonName = "xoa.local";
};
let
  inherit (lib) mkIf mkOption mkEnableOption types;

  cfg = config.xoa.xo;

  # Source tree of Xen Orchestra (pin via options below).
  xoSrc = pkgs.fetchFromGitHub {
    owner = cfg.repoOwner;
    repo  = cfg.repoName;
    rev   = cfg.srcRev;
    hash  = cfg.srcHash;    # <- SRI, e.g. "sha256-…"
    fetchSubmodules = true;
  };

  # A one-shot builder we run inside the xo-build service.
  xoBuildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euo pipefail
    umask 022

    app=/var/lib/xo/app

    # Ensure skeleton exists and is owned properly.
    install -d -m0750 -o ${cfg.user} -g ${cfg.user} "$app" \
      /var/cache/xo /var/cache/xo/yarn /var/log/xo

    # (Re)populate sources only when missing or rev changed.
    if [ ! -f "$app/.xo-src-rev" ] || [ "$(cat "$app/.xo-src-rev" 2>/dev/null || true)" != "${cfg.srcRev}" ]; then
      rm -rf "$app"/*
      cp -aT ${xoSrc} "$app"
      chown -R ${cfg.user}:${cfg.user} "$app"
      echo "${cfg.srcRev}" > "$app/.xo-src-rev"
    fi

    cd "$app"
    export PATH=${pkgs.nodejs_22}/bin:${pkgs.yarn}/bin:$PATH
    export HOME=/var/lib/xo
    export YARN_CACHE_FOLDER=/var/cache/xo/yarn
    export NODE_ENV=production
    export NODE_OPTIONS="--max-old-space-size=2048"

    # Install & build the mono‑repo
    yarn install --frozen-lockfile --non-interactive --no-progress
    yarn build
  '';

  nodeBin = "${pkgs.nodejs_22}/bin/node";

  # Default config written once if /etc/xo-server/config.toml is missing
  xoDefaultConfig = pkgs.writeText "xo-config.toml" ''
    # XO server minimal config with HTTPS + Redis + xo-web
    [http]
    hostname = "0.0.0.0"
    port = 443
    cert = "${cfg.tls.certDir}/certificate.pem"
    key  = "${cfg.tls.certDir}/key.pem"

    [http.mounts]
    "/" = "/var/lib/xo/app/packages/xo-web/dist/"

    [redis]
    uri = "redis://127.0.0.1:6379"
  '';
in {
  options.xoa.xo = {
    enable = mkEnableOption "Xen Orchestra (from sources)";

    user = mkOption {
      type = types.str;
      default = "xo";
      description = "System user running XO services.";
    };

    repoOwner = mkOption {
      type = types.str; default = "vatesfr";
      description = "GitHub owner for xen-orchestra sources.";
    };

    repoName = mkOption {
      type = types.str; default = "xen-orchestra";
      description = "GitHub repo name for XO sources.";
    };

    srcRev = mkOption {
      type = types.str;
      default = "2dd451a7d933f27e550fac673029d8ab79aba70d"; # example pin
      description = "Git revision (commit or tag) for the XO sources.";
    };

    srcHash = mkOption {
      type = types.str;
      example = "sha256-REPLACE_WITH_PREFETCHED_HASH";
      description = "SRI sha256 of the above revision.";
    };

    tls.enable = mkOption { type = types.bool; default = true; };
    tls.certDir = mkOption { type = types.str;  default = "/var/lib/ssl"; };
    tls.commonName = mkOption { type = types.str; default = "xoa.local"; };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
      # Build & remote-mount tools XO tends to need.
      environment.systemPackages = with pkgs; [
        nodejs_22 yarn git python3 pkg-config gcc gnumake libpng openssl
        nfs-utils cifs-utils lvm2 ntfs3g
      ];

      # Allow the XO service user to mount/umount NFS/SMB (passwordless sudo for those binaries only).
      security.sudo.enable = true;
      security.sudo.extraRules = [{
        users = [ cfg.user ];
        commands = [
          { command = "${pkgs.util-linux}/bin/mount";       options = [ "NOPASSWD" ]; }
          { command = "${pkgs.util-linux}/bin/umount";      options = [ "NOPASSWD" ]; }
          { command = "${pkgs.nfs-utils}/bin/mount.nfs";    options = [ "NOPASSWD" ]; }
          { command = "${pkgs.cifs-utils}/bin/mount.cifs";  options = [ "NOPASSWD" ]; }
        ];
      }];

      # Simple Redis instance for XO (no password by request).
      services.redis.servers.xo = {
        enable = true;
        save = [ ];
        appendOnly = false;
      };

      # Ensure directories and permissions exist early.
      systemd.tmpfiles.rules = [
        "d /var/lib/xo          0750 ${cfg.user} ${cfg.user} -"
        "d /var/lib/xo/app      0750 ${cfg.user} ${cfg.user} -"
        "d /var/cache/xo        0750 ${cfg.user} ${cfg.user} -"
        "d /var/cache/xo/yarn   0750 ${cfg.user} ${cfg.user} -"
        "d /var/log/xo          0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.tls.certDir}   0750 root       root       -"
        "d /etc/xo-server       0750 root       root       -"
      ];

      # Self-signed certs created if missing (first boot). Safe to keep as-is.
      systemd.services."xo-certgen" = {
        description = "Generate self-signed certificate for XO (first boot)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "xo-certgen.sh" ''
            set -euo pipefail
            cert="${cfg.tls.certDir}/certificate.pem"
            key="${cfg.tls.certDir}/key.pem"
            if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
              umask 077
              ${pkgs.openssl}/bin/openssl req -new -newkey rsa:4096 -x509 -sha256 -days 825 \
                -nodes -subj "/CN=${cfg.tls.commonName}" \
                -keyout "$key" -out "$cert"
              chown root:root "$key" "$cert"
              chmod 0640 "$key" "$cert"
            fi
          '';
        };
      };

      # Bootstrap (kept minimal; creates dirs).
      systemd.services."xo-bootstrap" = {
        description = "Prepare Xen Orchestra directories";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "xo-bootstrap.sh" ''
            set -euo pipefail
            install -d -m0750 -o ${cfg.user} -g ${cfg.user} /var/lib/xo/app /var/cache/xo/yarn /var/log/xo
          '';
        };
      };

      # Build from sources under /var/lib/xo/app
      systemd.services."xo-build" = {
        description = "Build Xen Orchestra (sources pinned via options)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "xo-bootstrap.service" ];
        wants = [ "network-online.target" "xo-bootstrap.service" ];
        environment = {
          HOME = "/var/lib/xo";
          YARN_CACHE_FOLDER = "/var/cache/xo/yarn";
          NODE_ENV = "production";
        };
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.user;

          # Let systemd prepare /var/lib/xo, /var/cache/xo, /var/log/xo with correct ownership.
          StateDirectory = [ "xo" "xo/app" ];
          CacheDirectory = [ "xo" "xo/yarn" ];
          LogsDirectory  = [ "xo" ];

          WorkingDirectory = "/var/lib/xo/app";
          PermissionsStartOnly = true;  # ExecStartPre runs as root

          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m0750 -o ${cfg.user} -g ${cfg.user} /var/lib/xo/app /var/cache/xo/yarn /var/log/xo"
            "${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.user} /var/lib/xo /var/cache/xo /var/log/xo"
          ];
          ExecStart = "${xoBuildScript}";

          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      # Run xo-server serving the built xo-web
      systemd.services."xo-server" = {
        description = "Xen Orchestra server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "xo-build.service" ];
        wants = [ "network-online.target" "xo-build.service" ];

        environment = {
          HOME = "/var/lib/xo";
          NODE_ENV = "production";
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.user;

          StateDirectory = [ "xo" "xo/app" ];
          CacheDirectory = [ "xo" "xo/yarn" ];
          LogsDirectory  = [ "xo" ];

          WorkingDirectory = "/var/lib/xo/app";

          # Drop in a sensible default config the first time only.
          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m0750 /etc/xo-server"
            "${pkgs.coreutils}/bin/test -e /etc/xo-server/config.toml || ${pkgs.coreutils}/bin/install -m0640 -o root -g root ${xoDefaultConfig} /etc/xo-server/config.toml"
          ];

          # Explicit start; config path is absolute so mounts work regardless of CWD.
          ExecStart = "${nodeBin} ./packages/xo-server/bin/xo-server --config /etc/xo-server/config.toml";

          Restart = "on-failure";
          RestartSec = "2s";

          # Hardening (still allows write to the 3 dirs + TLS dir)
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = "read-only";
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/xo"
            "/var/cache/xo"
            "/var/log/xo"
            "${cfg.tls.certDir}"
            "/etc/xo-server"
          ];
        };
      };
    }
  ]);
}
