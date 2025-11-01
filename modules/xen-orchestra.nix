{ config, pkgs, lib, xoCommit ? "afadc8f95adf741611d1f298dfe77cbf1f895231", ... }:

let
  inherit (lib) mkIf mkMerge optionalAttrs;

  # System paths and service user
  xoUser    = "xo";
  xoGroup   = "xo";
  xoRootDir = "/var/lib/xo";                # working tree for build/run
  sslDir    = "/var/lib/ssl";               # self-signed cert/key location
  etcDir    = "/etc/xo-server";             # root-editable config dir
  webDist   = "${xoRootDir}/app/packages/xo-web/dist";  # served static UI

  # Fetch upstream sources pinned to your chosen commit (official Vates repo).
  # Replace 'hash' after first build using the "got: sha256-..." Nix hint.
  xoSrc = pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo  = "xen-orchestra";
    rev   = xoCommit;
    # placeholder; Nix will tell you the correct narHash to paste here
    hash  = lib.fakeSha256;
    fetchSubmodules = true;
  };

  # Helper: tiny wrapper to make writing shell scripts readable
  sh = pkgs.writeShellScriptBin;

in
{
  #### 1) Base OS bits the service needs ####
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.groups.${xoGroup} = { };
  users.users.${xoUser} = {
    isSystemUser = true;
    group        = xoGroup;
    description  = "Xen Orchestra service";
    home         = xoRootDir;
    createHome   = true;
  };

  # Required filesystem helpers and build toolchain for XO from sources.
  # Docs: Node LTS + Yarn, Redis, libpng, libvhdi, lvm2, cifs/nfs, ntfs-3g, openssl. :contentReference[oaicite:7]{index=7}
  environment.systemPackages = with pkgs; [
    nodejs_22 yarn git python3 pkg-config gcc gnumake libpng openssl
    nfs-utils cifs-utils lvm2 ntfs3g libvhdi
  ];

  boot.supportedFilesystems = [ "nfs" "cifs" ];
  networking.firewall.allowedTCPPorts = [ 22 80 443 3389 5900 8012 ];

  # Redis (no password; localhost only) — mirrors upstream "from sources" guidance. :contentReference[oaicite:8]{index=8}
  services.redis.servers."xo" = {
    enable = true;
    # Bind loopback; protected mode by default (module sets sensible defaults).
    # Uncomment if you want explicit settings:
    # settings = { bind = "127.0.0.1"; "protected-mode" = "yes"; port = 6379; };
  };

  #### 2) Persistent dirs & config placement ####
  systemd.tmpfiles.rules = [
    "d ${xoRootDir} 0750 ${xoUser} ${xoGroup} -"
    "d ${xoRootDir}/app 0750 ${xoUser} ${xoGroup} -"
    "d ${sslDir} 0750 root ${xoGroup} -"
    "d ${etcDir} 0755 root root -"
    # runtime mounts directory used by XO remotes
    "d /run/xo-server/mounts 0755 ${xoUser} ${xoGroup} -"
  ];

  # Expose the upstream sources read-only under /etc for reference (optional)
  environment.etc."xo-src".source = xoSrc;

  #### 3) One-shot bootstrap: copy sample config & generate certs if missing ####
  systemd.services."xo-bootstrap" = {
    description = "XO bootstrap (seed config + self-signed HTTPS certs)";
    after  = [ "network-online.target" "redis-xo.service" ];
    wants  = [ "redis-xo.service" ];
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
          # Keep the upstream sample alongside for reference
          cp -f ${xoSrc}/packages/xo-server/sample.config.toml "$XO_ETC/config.toml.default"

          # Write our working config (root-editable, xo-readable)
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
      '');
    };
    wantedBy = [ "multi-user.target" ];
  };

  #### 4) Build from sources (yarn install && yarn build) ####
  systemd.services."xo-build" = {
    description = "Build Xen Orchestra (sources pinned)";
    after  = [ "network-online.target" "xo-bootstrap.service" ];
    wants  = [ "xo-bootstrap.service" ];
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

        # Build per upstream instructions: yarn && yarn build
        ${pkgs.yarn}/bin/yarn install --frozen-lockfile
        ${pkgs.yarn}/bin/yarn build
      '');
    };
    wantedBy = [ "multi-user.target" ];
  };

  #### 5) xo-server service (rootless, binds :80/:443, can mount NFS/SMB via sudo) ####
  systemd.services."xo-server" = {
    description = "Xen Orchestra Server";
    after    = [ "network-online.target" "redis-xo.service" "xo-build.service" "xo-bootstrap.service" ];
    requires = [ "redis-xo.service" "xo-build.service" "xo-bootstrap.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = xoUser;
      Group = xoGroup;

      WorkingDirectory = "${xoRootDir}/app/packages/xo-server";
      # Prepare runtime mounts dir (some XO remote types use it)
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/xo-server/mounts";

      # Run XO (reads /etc/xo-server/config.toml we created)
      ExecStart = "${pkgs.nodejs_22}/bin/node dist/cli.mjs";

      # Let non-root bind 80 & 443
      AmbientCapabilities   = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";

      Restart = "always";
      RestartSec = "2s";
    };
  };

  #### 6) Sudo rules: allow just what XO needs, passwordless for service user ####
  # Docs: running non-root requires sudo to mount NFS (same applies to SMB). :contentReference[oaicite:11]{index=11}
  security.sudo.enable = true;
  # Keep general wheel actions passworded; XO service gets NOPASSWD for specific helpers only.
  security.sudo.wheelNeedsPassword = true;
  security.sudo.extraRules = [{
    users = [ xoUser ];
    commands = [
      # Core mount ops
      { command = "/run/current-system/sw/bin/mount";   options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/umount";  options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/findmnt"; options = [ "NOPASSWD" ]; }
      # Filesystem-specific helpers
      { command = "/run/current-system/sw/sbin/mount.cifs"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/sbin/mount.nfs";  options = [ "NOPASSWD" ]; }
      # Loop devices are used occasionally (file-level ops/exports)
      { command = "/run/current-system/sw/sbin/losetup";     options = [ "NOPASSWD" ]; }
    ];
  }];

}
