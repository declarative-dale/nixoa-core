# SPDX-License-Identifier: Apache-2.0
# autocert.nix - Automatic TLS Certificate Generation
# ============================================================================
# Handles automatic generation and renewal of self-signed TLS certificates
# for Xen Orchestra HTTPS when enabled.
#
# Only generates certificates when:
# - Certificate or key files are missing
# - Existing certificate is expired
# - Certificate is valid and present → skips generation
#
# Controlled via nixoa.toml:
#   [tls]
#   autoGenerate = true  # defaults to true
#
# Set to false to disable automatic cert generation (e.g., when using ACME)
# ============================================================================

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.nixoa.xo;
  tlsCfg = config.nixoa.xo.tls;
  httpCfg = config.nixoa.xo.http;
  autocertCfg = config.nixoa.autocert;
  xoUser = config.nixoa.xo.service.user;
  xoGroup = config.nixoa.xo.service.group;
  openssl = pkgs.openssl;

  # Script to generate or renew certificates only when needed
  genCertScript = pkgs.writeShellScript "xoa-generate-certs.sh" ''
    set -euo pipefail
    umask 077

    cert="${tlsCfg.cert}"
    key="${tlsCfg.key}"
    host="${config.networking.hostName}"

    # Ensure cert directory exists with proper permissions
    mkdir -p "${tlsCfg.dir}"
    chmod 0755 "${tlsCfg.dir}"

    # Only generate if cert or key missing, or certificate expired
    if [ ! -s "$key" ] || [ ! -s "$cert" ]; then
      echo "No existing certificate found – generating new self-signed cert."
    elif ! ${openssl}/bin/openssl x509 -checkend 0 -noout -in "$cert" 2>/dev/null; then
      echo "Certificate expired – regenerating self-signed cert."
    else
      echo "Certificate exists and is valid – skipping generation."
      exit 0
    fi

    # Generate a 10-year self-signed certificate
    echo "Generating 10-year self-signed certificate for $host..."
    ${openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
      -keyout "$key" -out "$cert" \
      -subj "/CN=$host" \
      -addext "subjectAltName=DNS:$host,DNS:localhost,IP:${httpCfg.host}"

    # Set proper ownership and permissions
    chown ${xoUser}:${xoGroup} "$key" "$cert"
    chmod 0640 "$key" "$cert"

    echo "Certificate generation complete."
  '';
in
{
  options.nixoa.autocert = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable automatic self-signed TLS certificate generation for XO HTTPS.

        When enabled, certificates are generated or renewed only when:
        - Certificate or key files are missing
        - Existing certificate is expired

        Disable this if using ACME or providing your own certificates.
      '';
    };
  };

  config = mkIf (cfg.enable && autocertCfg.enable && tlsCfg.enable) {
    # Systemd service to generate/renew certificates at boot
    systemd.services.xo-autocert = {
      description = "Generate XO TLS certificates if missing or expired";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
      before = [ "xo-build.service" "xo-server.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = genCertScript;
        User = "root";
        Group = "root";
      };
    };
  };
}
