# SPDX-License-Identifier: Apache-2.0
# autocert.nix - Automatic TLS Certificate Generation for Xen Orchestra
# ============================================================================
# Handles automatic generation and renewal of self-signed TLS certificates
# for Xen Orchestra HTTPS.
#
# Only generates certificates when:
# - Certificate or key files are missing
# - Existing certificate is expired
# - Certificate is valid and present → skips generation
#
# Controlled via system/flake.nix vars:
#   enableAutoCert = true  # Simple true/false toggle
#
# Set to false to disable automatic cert generation (e.g., when using ACME)
# ============================================================================

{
  config,
  pkgs,
  lib,
  vars,
  ...
}:

let
  inherit (lib) mkIf;

  # Reference TLS configuration from xoa module
  tlsCfg = config.nixoa.xo.tls;

  xoUser = vars.xoUser;
  xoGroup = vars.xoGroup;
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
      -addext "subjectAltName=DNS:$host,DNS:localhost,IP:${vars.xoHttpHost}"

    # Set proper ownership and permissions
    chown ${xoUser}:${xoGroup} "$key" "$cert"
    chmod 0640 "$key" "$cert"

    echo "Certificate generation complete."
  '';
in
{
  # Only activate when enableAutoCert is true
  config = mkIf vars.enableAutoCert {
    # Systemd service to generate/renew certificates at boot
    systemd.services.xo-autocert = {
      description = "Generate XO TLS certificates if missing or expired";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-tmpfiles-setup.service"
      ];
      before = [
        "xo-server.service"
      ];

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
