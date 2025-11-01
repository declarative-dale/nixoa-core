{ config, pkgs, lib, xoCommit ? "afadc8f95adf741611d1f298dfe77cbf1f895231", ... }:

let
  inherit (lib) mkIf mkMerge optional optionalAttrs;

  xoUser    = "xo";
  xoGroup   = "xo";
  xoRootDir = "/var/lib/xo";
  sslDir    = "/var/lib/ssl";
  etcDir    = "/etc/xo-server";
  webDist   = "${xoRootDir}/app/packages/xo-web/dist";

  xoSrc = pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo  = "xen-orchestra";
    rev   = xoCommit;
    # Replace after first build with the narHash Nix prints
    hash  = lib.fakeSha256;
    fetchSubmodules = true;
  };

in {
  # Service account for xo-server
  users.groups.${xoGroup} = { };
  users.users.${xoUser} = {
    isSystemUser = true;
    group        = xoGroup;
    description  = "Xen Orchestra service";
    home         = xoRootDir;
    createHome   = true;
  };

  # Tooling needed to build and run XO from sources (per upstream docs)
  environment.systemPackages = with pkgs; [
    nodejs_22 yarn git python3 pkg-config gcc gnumake libpng openssl
    nfs-utils cifs-utils lvm2 ntfs3g
  ];

  # Redis (no password; localhost)
  services.redis.servers."xo".enable = true;

  # Persistent dirs & runtime paths
  systemd.tmpfiles.rules = [
    "d ${xoRootDir} 0750 ${xoUser} ${xoGroup} -"
    "d ${xoRootDir}/app 0750 ${xoUser} ${xoGroup} -"
    "d ${sslDir} 0750 root ${xoGroup} -"
    "d ${etcDir} 0755 root root -"
    "d /run/xo-server/mounts 0755 ${xoUser} ${xoGroup} -"
  ];

  # Bootstrap: create self-signed cert + initial config from sample if missing
  systemd.services."xo-bootstrap" = {
    description = "XO bootstrap (seed config + self-signed HTTPS certs)";
    after  = [ "network-online.target" "redis-xo.service" ];
    wants  = [ "network-online.target" "redis-xo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      Environment = [ "SSL_DIR=${sslDir}" "XO_ETC=${etcDir}" "XO_APP=${xoRootDir}/app" ];
      ExecStart = (pkgs.writeShellScript "xo-bootstrap.sh" ''
        set -euo pipefail

        # 1) Create HTTPS key/cert on first run if missing (kept OUT of Nix store).
        if [ ! -s "$SSL_DIR/key.pem" ] || [ ! -s "$SSL_DIR/certificate.pem" ]; then
          ${pkgs.openssl}/bin/openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/CN=xoa.local" \
            -keyout "$SSL_DIR/key.pem" \
            -out    "$SSL_DIR/certificate.pem"
          chown root:${xoGroup} "$SSL_DIR/key.pem" "$SSL_DIR/certificate.pem"
          chmod 0640 "$SSL_DIR/key.pem"
          chmod 0644 "$SSL_DIR/certificate.pem"
        fi

        # 2) Create /etc/xo-server/config.toml from upstream sample (root-editable)
        if [ ! -s "$XO_ETC/config.toml" ]; then
          mkdir -p "$XO_ETC"
          cp -f ${xoSrc}/packages/xo-server/sample.config.toml "$XO_ETC/config.toml.default"

          cat > "$XO_ETC/config.toml" <<'TOML'
# Generated from upstream sample.config.toml on first activation.
# Edit this file as root; restart xo-server to apply changes.

user = 'xo'
group = 'xo'
useSudo = true

[http]
hostname = '0.0.0.0'
port = 80
redirectToHttps = true

[https]
hostname = '0.0.0.0'
port = 443
certificate = '${sslDir}/certificate.pem'
key         = '${sslDir}/key.pem'

[http.mounts]
'/' = '${webDist}'
TOML
          chown root:root "$XO_ETC/config.toml"
          chmod 0644 "$XO_ETC/config.toml"
        fi
      '' );
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Build XO from sources
  systemd.services."xo-build" = {
    description = "Build Xen Orchestra (sources pinned)";
    after  = [ "network-online.target" "xo-bootstrap.service" ];
    wants  = [ "network-online.target" "xo-bootstrap.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = xoUser;
      Group = xoGroup;
      WorkingDirectory = "${xoRootDir}/app";
      Environment = [ "HOME=${xoRootDir}" ];
      ExecStart = (pkgs.writeShellScript "xo-build.sh" ''
        set -euo pipefail
        rm -rf "${xoRootDir}/app/"*
        cp -a ${xoSrc}/. "${xoRootDir}/app/"

        ${pkgs.yarn}/bin/yarn install --frozen-lockfile
        ${pkgs.yarn}/bin/yarn build
      '' );
    };
    wantedBy = [ "multi-user.target" ];
  };

  # xo-server service
  systemd.services."xo-server" = {
    description = "Xen Orchestra Server";
    after    = [ "network-online.target" "redis-xo.service" "xo-build.service" "xo-bootstrap.service" ];
    requires = [ "redis-xo.service" "xo-build.service" "xo-bootstrap.service" ];
    wants    = [ "network-online.target" "redis-xo.service" "xo-build.service" "xo-bootstrap.service" ];
    serviceConfig = {
      User = xoUser;
      Group = xoGroup;
      WorkingDirectory = "${xoRootDir}/app/packages/xo-server";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/xo-server/mounts";
      ExecStart = "${pkgs.nodejs_22}/bin/node dist/cli.mjs";
      AmbientCapabilities   = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
      Restart = "always";
      RestartSec = "2s";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Sudo rules for the service user (mount/umount helpers)
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = true;
  security.sudo.extraRules = [{
    users = [ xoUser ];
    commands = [
      { command = "/run/current-system/sw/bin/mount";        options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/umount";       options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/findmnt";      options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/sbin/mount.cifs";  options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/sbin/mount.nfs";   options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/sbin/losetup";     options = [ "NOPASSWD" ]; }
    ];
  }];
}
