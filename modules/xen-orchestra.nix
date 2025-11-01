{ lib, pkgs, config, ... }:

let
  cfg = config.xoa.xo;

  # Service runtime layout
  xoUser    = "xo";
  xoGroup   = "xo";     # ensure users.nix defines this group as the xo user's primary group
  xoRootDir = "/var/lib/xo";
  sslDir    = "/var/lib/ssl";
  etcDir    = "/etc/xo-server";
  webDist   = "${xoRootDir}/app/packages/xo-web/dist";

  # Source fetch (uses module options for commit/hash)
  xoSrc = pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo  = "xen-orchestra";
    rev   = cfg.rev;        # Git commit or tag (set in system.nix)
    fetchSubmodules = true;
    hash  = cfg.srcHash;    # SRI sha256 of the extracted source
  };

in
{
  #######################################
  ## 1) Module options (typed)
  #######################################
  options.xoa.xo = {
    enable = lib.mkEnableOption "Build and run Xen Orchestra (xo-server) from source";

    rev = lib.mkOption {
      type = lib.types.str;
      # You can override this in system.nix; default shown here for convenience.
      default = "2dd451a7d933f27e550fac673029d8ab79aba70d";
      description = ''
        Git revision (commit or tag) of vatesfr/xen-orchestra to build.
      '';
      example = "2dd451a7d933f27e550fac673029d8ab79aba70d";
    };

    srcHash = lib.mkOption {
      type = lib.types.str;
      # Trust-on-first-use: let Nix print the “got: sha256-…” once, then paste it here.
      default = lib.fakeSha256;
      description = ''
        SRI sha256 of the extracted source at `rev`. Use lib.fakeSha256 initially,
        build once, copy the “got: sha256-…” that Nix prints, and set it here.
      '';
      example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };

  #######################################
  ## 2) Configuration (only when enabled)
  #######################################
  config = lib.mkIf cfg.enable {

    # Tooling needed to build/run XO from sources (per XO docs: Node LTS, Yarn, Redis, libpng, LVM, CIFS/NFS, NTFS, OpenSSL).
    environment.systemPackages = with pkgs; [
      nodejs_22 yarn git python3 pkg-config gcc gnumake libpng openssl
      nfs-utils cifs-utils lvm2 ntfs3g
    ];

    # Local Redis instance (no password; vxdb 0 on 127.0.0.1)
    services.redis.servers."xo".enable = true;

    # Persistent dirs & runtime paths
    systemd.tmpfiles.rules = [
      "d ${xoRootDir} 0750 ${xoUser} ${xoGroup} -"
      "d ${xoRootDir}/app 0750 ${xoUser} ${xoGroup} -"
      "d ${sslDir} 0750 root ${xoGroup} -"
      "d ${etcDir} 0755 root root -"
      "d /run/xo-server/mounts 0755 ${xoUser} ${xoGroup} -"
    ];

    # Bootstrap once: seed config from upstream sample; generate self-signed TLS if missing
    systemd.services."xo-bootstrap" = {
      description = "XO bootstrap (seed config + self‑signed HTTPS certs)";
      after  = [ "network-online.target" "redis-xo.service" ];
      wants  = [ "network-online.target" "redis-xo.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        Environment = [
          "SSL_DIR=${sslDir}"
          "XO_ETC=${etcDir}"
          "XO_APP=${xoRootDir}/app"
        ];
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

            cat > "$XO_ETC/config.toml" <<TOML
# Generated from upstream sample.config.toml on first activation.
# Edit this file as root; restart xo-server to apply changes.
# Config path reference: /etc/xo-server/config.toml

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
        '');
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Build Xen Orchestra from sources at the selected rev/hash
    systemd.services."xo-build" = {
      description = "Build Xen Orchestra (sources pinned via options)";
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
          # copy sources from Nix store into a writable tree
          cp -a ${xoSrc}/. "${xoRootDir}/app/"

          # Upstream flow: yarn install && yarn build
          ${pkgs.yarn}/bin/yarn install --frozen-lockfile
          ${pkgs.yarn}/bin/yarn build
        '');
      };
      wantedBy = [ "multi-user.target" ];
    };

    # xo-server runtime (rootless; binds 80/443 via caps; reads /etc/xo-server/config.toml)
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

        # allow binding low ports as non-root
        AmbientCapabilities   = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";

        Restart = "always";
        RestartSec = "2s";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Passwordless sudo for the service user — least privilege for mount helpers
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
        { command = "/run/current-system/sw/bin/losetup";      options = [ "NOPASSWD" ]; }
      ];
    }];
  };
}
