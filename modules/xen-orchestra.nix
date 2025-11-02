{ lib, pkgs, config, ... }:

let
  inherit (lib) mkEnableOption mkOption types mkIf optionalString hasAttrByPath;
  cfg = config.xoa.xo;

  # Fetch the pinned XO sources; must be copied out of /nix/store to build (yarn writes)
  xoSrc = pkgs.fetchFromGitHub {
    owner = "vatesfr";
    repo  = "xen-orchestra";
    rev   = cfg.srcRev;   # e.g. "2dd451a7d933f27e550fac673029d8ab79aba70d"
    hash  = cfg.srcHash;  # e.g. "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  };

  buildDir = cfg.buildDir;           # usually /var/lib/xo
  appDir   = "${buildDir}/app";
  tlsDir   = "${buildDir}/tls";
  cacheDir = "${buildDir}/yarn-cache";

  # Helper scripts
  bootstrapScript = pkgs.writeShellScript "xo-bootstrap.sh" ''
    set -euo pipefail

    # Ensure directories exist & ownership
    install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${buildDir} ${appDir} ${tlsDir} ${cacheDir}

    # Seed a writable working tree from the Nix store if missing or if rev changed
    if [ ! -d "${appDir}/.git" ] || [ ! -f "${buildDir}/REV" ] || [ "$(cat ${buildDir}/REV)" != "${cfg.srcRev}" ]; then
      rm -rf "${appDir}"
      mkdir -p "${appDir}"
      cp -R --no-preserve=mode ${xoSrc}/* "${appDir}/"
      chown -R ${cfg.user}:${cfg.group} "${appDir}"
      echo "${cfg.srcRev}" > "${buildDir}/REV"
    fi

    # Generate self-signed TLS certs if missing
    if [ ! -s "${tlsDir}/key.pem" ] || [ ! -s "${tlsDir}/certificate.pem" ]; then
      ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 825 \
        -nodes -keyout "${tlsDir}/key.pem" -out "${tlsDir}/certificate.pem" \
        -subj "/CN=${cfg.tls.commonName}" \
        -addext "subjectAltName=DNS:${cfg.tls.commonName}"
      chown ${cfg.user}:${cfg.group} "${tlsDir}/key.pem" "${tlsDir}/certificate.pem"
      chmod 0640 "${tlsDir}/key.pem"
      chmod 0644 "${tlsDir}/certificate.pem"
    fi

    # Create an editable config if missing (XO reads /etc/xo-server/config.toml)
    if [ ! -e /etc/xo-server/config.toml ]; then
      install -D -m 0640 -o root -g ${cfg.group} /dev/null /etc/xo-server/config.toml
      cat > /etc/xo-server/config.toml <<'EOF'
# Generated once by xo-bootstrap (you own this file; edit as root and restart xo-server)
# See: https://github.com/vatesfr/xen-orchestra/tree/master/packages/xo-server (sample.config.toml)
[http]
port = 80
redirectToHttps = true

[https]
port = 443
certificate = "${tlsDir}/certificate.pem"
key = "${tlsDir}/key.pem"
EOF
    fi
  '';

  buildScript = pkgs.writeShellScript "xo-build.sh" ''
    set -euo pipefail
    export HOME='${buildDir}'
    export YARN_CACHE_FOLDER='${cacheDir}'
    cd '${appDir}'

    # Use the yarn that matches the repo via Corepack
    ${pkgs.nodejs_22}/bin/corepack enable
    # If the repo already pins yarn via .yarnrc.yml/yarnPath this is a no-op:
    ${pkgs.nodejs_22}/bin/corepack prepare yarn@stable --activate

    ${pkgs.nodejs_22}/bin/yarn --immutable
    ${pkgs.nodejs_22}/bin/yarn build
  '';
in
{
  #### Module options ###########################################################
  options.xoa.xo = {
    enable = mkEnableOption "Build & run Xen Orchestra (from source)";

    user = mkOption {
      type = types.str;
      default = "xo";
      description = "Unix user that builds/runs XO.";
    };

    group = mkOption {
      type = types.str;
      default = "xo";
      description = "Group owning XO state.";
    };

    # Pin to a specific upstream commit/tag
    srcRev = mkOption {
      type = types.str;
      example = "2dd451a7d933f27e550fac673029d8ab79aba70d";
      description = "Git rev (commit or tag) in vatesfr/xen-orchestra.";
    };

    # Required content hash for srcRev (SRI or legacy sha256)
    srcHash = mkOption {
      type = types.str;
      example = "sha256-TpXyd7DohHG50HvxzfNmWVtiW7BhGSxWk+3lgFMMf/M=";
      description = ''
        Hash of the fetched source. Compute with:
          nix-prefetch fetchFromGitHub --owner vatesfr --repo xen-orchestra --rev <rev>
        or:
          nix run nixpkgs#nix-prefetch-github -- vatesfr xen-orchestra --rev <rev>
      '';
    };

    buildDir = mkOption {
      type = types.path;
      default = "/var/lib/xo";
      description = "Writable state/work directory for XO sources and cache.";
    };

    tls.commonName = mkOption {
      type = types.str;
      default = "localhost";
      description = "CN/SAN used for the generated self-signed certificate.";
    };

    http.port = mkOption { type = types.port; default = 80;  description = "HTTP listen port."; };
    https.port = mkOption { type = types.port; default = 443; description = "HTTPS listen port."; };
  };

  #### Implementation ###########################################################
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = hasAttrByPath [ "users" "users" cfg.user ] config;
        message   = "User '${cfg.user}' must exist (define it in users.nix).";
      }
      {
        assertion = cfg.srcHash != "";
        message   = "xoa.xo.srcHash must be set to the SRI for ${cfg.srcRev}.";
      }
    ];

    environment.systemPackages = with pkgs; [
      nodejs_22 git pkg-config python3 gcc gnumake
      openssl cifs-utils nfs-utils lvm2 ntfs3g
    ];

    # Redis (no password, per your earlier request)
    services.redis.servers.xo = {
      enable = true;
      port = 6379;
      user = cfg.user;
      # dataDir left default under /var/lib/redis-xo
    };

    # Open firewall for XO
    networking.firewall.allowedTCPPorts = [ cfg.http.port cfg.https.port ];

    # Create necessary dirs at boot (generic tmpfiles facility)
    # (tmpfiles.d is a standard way to create/manage dirs at activation)
    systemd.tmpfiles.rules = [
      "d ${buildDir}       0750 ${cfg.user} ${cfg.group} - -"
      "d ${appDir}         0750 ${cfg.user} ${cfg.group} - -"
      "d ${tlsDir}         0750 ${cfg.user} ${cfg.group} - -"
      "d ${cacheDir}       0750 ${cfg.user} ${cfg.group} - -"
      "d /etc/xo-server    0755 root       ${cfg.group} - -"
    ]; # :contentReference[oaicite:1]{index=1}

    # One-shot bootstrap: copy sources out of the store, seed config, generate TLS
    systemd.services.xo-bootstrap = {
      description = "Prepare Xen Orchestra working tree, config, and TLS";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # The service itself needs no network, but ordering avoids races when your next units fetch plugins, etc.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = bootstrapScript;
      };
      wantedBy = [ "multi-user.target" ];
    }; # :contentReference[oaicite:2]{index=2}

    # Build from the writable working tree with yarn/corepack
    systemd.services.xo-build = {
      description = "Build Xen Orchestra (sources pinned via xoa.xo.{srcRev,srcHash})";
      after = [ "xo-bootstrap.service" "network-online.target" ];
      wants = [ "xo-bootstrap.service" "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = appDir;
        # Make sure these dirs are ours and writable before we build
        ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.user} -g ${cfg.group} ${appDir} ${cacheDir}";
        ExecStart = buildScript;

        # Keep writes confined to these paths
        ReadWritePaths = [ buildDir "/etc/xo-server" ];
        # Provide a runtime tmp dir
        RuntimeDirectory = "xo";
        StateDirectory   = "xo";     # creates /var/lib/xo with correct perms for us
        CacheDirectory   = "xo";     # creates /var/cache/xo if needed
        Environment = [
          "HOME=${buildDir}"
          "YARN_CACHE_FOLDER=${cacheDir}"
        ];
      };
      wantedBy = [ "multi-user.target" ];
    }; # :contentReference[oaicite:3]{index=3}

    # Run xo-server (reads /etc/xo-server/config.toml)
    systemd.services.xo-server = {
      description = "Xen Orchestra (xo-server)";
      after  = [ "xo-build.service" "redis-xo.service" "network-online.target" ];
      wants  = [ "xo-build.service" "redis-xo.service" "network-online.target" ];
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = appDir;

        ExecStart = "${pkgs.nodejs_22}/bin/node ./packages/xo-server/dist/cli.mjs";

        # Allow binding to 443 without root
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";

        # Environment
        Environment = [
          "NODE_ENV=production"
          "HOME=${buildDir}"
        ];

        # Restart policy
        Restart = "on-failure";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Make sure network-online.target does what we think it does on your system
    systemd.network.wait-online.enable = lib.mkDefault true;
  };
}
