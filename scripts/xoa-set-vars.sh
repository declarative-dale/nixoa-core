#!/usr/bin/env bash
set -euo pipefail

VARS_FILE="vars.nix"

read -rp "Hostname [xoa]: " HOSTNAME
HOSTNAME=${HOSTNAME:-xoa}

read -rp "Admin username [xoa]: " USERNAME
USERNAME=${USERNAME:-xoa}

echo "Paste one or more SSH public keys. Finish with an empty line:"
SSH_KEYS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && break
  SSH_KEYS+=("$line")
done

# Copy hardware-configuration.nix once to the repo root if it exists on the system
if [[ -f /etc/nixos/hardware-configuration.nix && ! -e hardware-configuration.nix ]]; then
  echo "Copying /etc/nixos/hardware-configuration.nix -> ./hardware-configuration.nix"
  cp /etc/nixos/hardware-configuration.nix hardware-configuration.nix
else
  echo "Skipping hardware-configuration.nix copy (either it doesn't exist in /etc/nixos or it already exists here)."
fi

cat > "$VARS_FILE" <<EOF
{
  system   = "x86_64-linux";
  hostname = "${HOSTNAME}";
  username = "${USERNAME}";
  sshKeys  = [
$(for k in "${SSH_KEYS[@]}"; do printf '    "%s"\n' "$k"; done)
  ];

  xoHost      = "0.0.0.0";
  xoPort      = 80;
  xoHttpsPort = 443;
  tls = {
    enable = true;
    dir = "/etc/ssl/xo";
    cert = "/etc/ssl/xo/certificate.pem";
    key  = "/etc/ssl/xo/key.pem";
  };

  storage = {
    nfs.enable  = true;
    cifs.enable = true;
    mountsDir   = "/var/lib/xo/mounts";
  };
  xoUser  = "xo";
  xoGroup = "xo";
  stateVersion = "25.05";
}
EOF

echo "Wrote $VARS_FILE."
echo "If hardware-configuration.nix was present, it is now in ./hardware-configuration.nix."
