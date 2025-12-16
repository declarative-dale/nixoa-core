#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# NiXOA Bootstrap Installer
# This script bootstraps the NiXOA base flake and user configuration flake.
# It is idempotent and can be run multiple times safely.

set -euo pipefail

# Configuration
BASE_DIR="/etc/nixos/nixoa"          # Target location for base flake (nixoa-vm)
BASE_REPO="https://codeberg.org/nixoa/nixoa-vm.git"
USER_REPO_DIR="$HOME/user-config"    # Target location for user config flake (home directory)
USER_REPO_REMOTE=""                  # Will be prompted from user
DRY_RUN=false

# Parse arguments
if [[ ${1:-} == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY-RUN] Running in dry-run mode. No changes will be made."
fi

# Helper function to run or echo commands
run() {
  if $DRY_RUN; then
    echo "# (dry-run) $*"
  else
    echo ">>> $*"
    eval "$@"
  fi
}

# Ensure running as non-root
if [[ $EUID -eq 0 ]]; then
  echo "Please run this script as a regular user, not root."
  exit 1
fi

echo "NiXOA Bootstrap Installer starting..."
echo

# 1. Clone base flake (nixoa-vm) to /etc/nixos/nixoa
if [[ -d "$BASE_DIR/nixoa-vm" ]]; then
  echo "Base flake directory $BASE_DIR/nixoa-vm already exists."
  if [[ -d "$BASE_DIR/nixoa-vm/.git" ]]; then
    echo " - Git repository detected for base flake."
    # Optionally, you could pull latest changes:
    # run "sudo git -C $BASE_DIR/nixoa-vm pull"
  else
    echo " - Note: $BASE_DIR/nixoa-vm exists but is not a git repo."
  fi
else
  echo "Cloning base flake (nixoa-vm) to $BASE_DIR..."
  run "sudo mkdir -p $BASE_DIR"
  run "sudo git clone $BASE_REPO $BASE_DIR/nixoa-vm"
fi

# 2. Prompt for git user info if not set
GIT_NAME=$(git config --global user.name || true)
GIT_EMAIL=$(git config --global user.email || true)
if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
  echo "Git global identity not found. Setting up global Git config..."
  if [[ -z "$GIT_NAME" ]]; then
    read -rp "Enter your name for Git commits: " NAME
    if [[ -n "$NAME" ]]; then
      run "git config --global user.name \"$NAME\""
    fi
  fi
  if [[ -z "$GIT_EMAIL" ]]; then
    read -rp "Enter your email for Git commits: " EMAIL
    if [[ -n "$EMAIL" ]]; then
      run "git config --global user.email \"$EMAIL\""
    fi
  fi
fi

# 3. Set up user config flake repository in home directory
if [[ -d "$USER_REPO_DIR" ]]; then
  echo "User config directory $USER_REPO_DIR already exists."
  if [[ -d "$USER_REPO_DIR/.git" ]]; then
    echo " - Git repository detected for user config."
  else
    echo " - Initializing git in $USER_REPO_DIR (was not a repo)."
    run "git init \"$USER_REPO_DIR\""
  fi
else
  echo "Creating user config flake in $USER_REPO_DIR ..."
  run "mkdir -p \"$USER_REPO_DIR\""
  run "git init \"$USER_REPO_DIR\""
fi

# Optionally prompt for remote URL for user-config repo
if [[ $DRY_RUN == false ]]; then
  read -rp "Enter a git remote URL for your user-config (or leave blank to skip): " REPO_URL
  USER_REPO_REMOTE="$REPO_URL"
fi
if [[ -n "$USER_REPO_REMOTE" ]]; then
  echo "Setting origin remote for user-config to $USER_REPO_REMOTE"
  run "git -C \"$USER_REPO_DIR\" remote add origin \"$USER_REPO_REMOTE\" || true"
fi

# 4. Populate user config flake with initial files
# a) flake.nix
FLAKE_NIX_CONTENT='
{
  description = "User configuration flake for NiXOA";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      # Import the hardware config if present
      hardwareConfigPath = ./hardware-configuration.nix;
    in {
      # NixOS module for NiXOA (converts TOML to options)
      nixosModules.default = import ./modules/nixoa-config.nix;
      nixosModules.hardware =
        if builtins.pathExists hardwareConfigPath then import hardwareConfigPath
        else throw "Missing hardware-configuration.nix in user-config!";
      # Raw config data exports
      nixoa = {
        system = import ./modules/system.nix;
        xoServer.toml = import ./modules/xo-server-config.nix;
      };
    };
}
'
if [[ ! -f "$USER_REPO_DIR/flake.nix" ]]; then
  echo "Writing flake.nix to user config..."
  run "cat > \"$USER_REPO_DIR/flake.nix\" <<< '$FLAKE_NIX_CONTENT'"
fi

# b) system-settings.toml (if not exists, create from template)
if [[ ! -f "$USER_REPO_DIR/system-settings.toml" ]]; then
  echo "Creating initial system-settings.toml..."
  SETTINGS_CONTENT='[nixoa]
# NiXOA system basic settings
hostname = "nixoa"
stateVersion = "25.11"

[admin]
username = "xoa"
sshKeys = []
# Add your SSH public keys here, e.g.:
# sshKeys = [
#   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... user@laptop"
# ]

[xo]
host = "0.0.0.0"
port = 80
httpsPort = 443

[xo.service]
xoUser = "xo"
xoGroup = "xo"

[tls]
enable = true
redirectToHttps = true
autoGenerate = true
# cert/key paths can be left default
cert = "/etc/ssl/xo/certificate.pem"
key = "/etc/ssl/xo/key.pem"

[storage.nfs]
enable = true
[storage.cifs]
enable = true
[storage.vhd]
enable = true
mountsDir = "/var/lib/xo/mounts"

[networking.firewall]
allowedTCPPorts = [80, 443, 3389, 5900, 8012]

# Optionally, define updates, packages, services etc. per documentation
'
  run "cat > \"$USER_REPO_DIR/system-settings.toml\" <<'EOF'
$SETTINGS_CONTENT
EOF"
fi

# c) xo-server-settings.toml (ensure [nixoa] section exists)
if [[ ! -f "$USER_REPO_DIR/xo-server-settings.toml" ]]; then
  echo "Creating initial xo-server-settings.toml..."
  XO_SETTINGS_CONTENT='[nixoa]
# XO server configuration
raw_toml = """
# You can put custom XO-server configuration overrides here.
# By default, this is empty, meaning XO uses its defaults.
"""
'
  run "cat > \"$USER_REPO_DIR/xo-server-settings.toml\" <<'EOF'
$XO_SETTINGS_CONTENT
EOF"
fi

# d) modules and scripts
MODULES_DIR="$USER_REPO_DIR/modules"
SCRIPTS_DIR="$USER_REPO_DIR/scripts"
run "mkdir -p \"$MODULES_DIR\" \"$SCRIPTS_DIR\""

# Write nixoa-config.nix (TOML->NixOS conversion module)
if [[ ! -f "$MODULES_DIR/nixoa-config.nix" ]]; then
  echo "Writing modules/nixoa-config.nix..."
  NIXOA_CONFIG_CONTENT='{ lib, ... }:
let
  settings = builtins.fromTOML (builtins.readFile ../system-settings.toml);
  get = path: default:
    let val = builtins.tryEval (builtins.getAttrByPath path settings); in
    if val.success then val.value else default;
in {
  config.nixoa = {
    hostname = get ["nixoa" "hostname"] "nixoa";
    stateVersion = get ["nixoa" "stateVersion"] "25.11";
    admin = {
      username = get ["admin" "username"] "xoa";
      sshKeys = get ["admin" "sshKeys"] [];
    };
    xo = {
      host = get ["xo" "host"] "0.0.0.0";
      port = get ["xo" "port"] 80;
      httpsPort = get ["xo" "httpsPort"] 443;
      service = {
        user = get ["xo" "service" "xoUser"] "xo";
        group = get ["xo" "service" "xoGroup"] "xo";
      };
      tls = {
        enable = get ["tls" "enable"] true;
        redirectToHttps = get ["tls" "redirectToHttps"] true;
        autoGenerate = get ["tls" "autoGenerate"] true;
        dir = get ["tls" "dir"] "/etc/ssl/xo";
        cert = get ["tls" "cert"] "/etc/ssl/xo/certificate.pem";
        key = get ["tls" "key"] "/etc/ssl/xo/key.pem";
      };
    };
    storage = {
      nfs.enable = get ["storage" "nfs" "enable"] true;
      cifs.enable = get ["storage" "cifs" "enable"] true;
      vhd.enable = get ["storage" "vhd" "enable"] true;
      mountsDir = get ["storage" "mountsDir"] "/var/lib/xo/mounts";
    };
    networking.firewall.allowedTCPPorts = get ["networking" "firewall" "allowedTCPPorts"] [80 443 3389 5900 8012];
  };
}
'
  run "cat > \"$MODULES_DIR/nixoa-config.nix\" <<'EOF'
$NIXOA_CONFIG_CONTENT
EOF"
fi

# Write system.nix (raw system settings export)
if [[ ! -f "$MODULES_DIR/system.nix" ]]; then
  echo "Writing modules/system.nix..."
  SYSTEM_NIX_CONTENT='{ }:
builtins.fromTOML (builtins.readFile ../system-settings.toml)
'
  run "cat > \"$MODULES_DIR/system.nix\" <<'EOF'
$SYSTEM_NIX_CONTENT
EOF"
fi

# Write xo-server-config.nix (extract xoServer raw TOML)
if [[ ! -f "$MODULES_DIR/xo-server-config.nix" ]]; then
  echo "Writing modules/xo-server-config.nix..."
  XOSC_NIX_CONTENT='{ }:
let
  cfg = builtins.fromTOML (builtins.readFile ../xo-server-settings.toml);
  rawToml = cfg.nixoa.raw_toml or "";
in builtins.toString rawToml
'
  run "cat > \"$MODULES_DIR/xo-server-config.nix\" <<'EOF'
$XOSC_NIX_CONTENT
EOF"
fi

# Scripts: commit-config.sh, apply-config.sh, etc.
if [[ ! -f "$SCRIPTS_DIR/commit-config.sh" ]]; then
  echo "Adding commit-config.sh script..."
  COMMIT_SCRIPT_CONTENT='#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Commit configuration changes to the local git repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

cd "$CONFIG_DIR"

# Check if we are in a git repository
if [ ! -d .git ]; then
    echo "Error: Not a git repository."
    exit 1
fi

# Get commit message from argument or prompt
if [ $# -eq 0 ]; then
    echo "Usage: $0 <commit message>"
    echo "Example: $0 '"'"'Updated XO ports and TLS settings'"'"'"
    exit 1
fi

COMMIT_MSG="$1"

# Show what'"'"'s changed
echo "=== Configuration Changes ==="
git diff --stat system-settings.toml xo-server-settings.toml 2>/dev/null || true
echo ""

# Stage the TOML files
git add system-settings.toml xo-server-settings.toml

# Check if there are changes to commit
if git diff --staged --quiet; then
    echo "No changes to commit."
    exit 0
fi

# Commit the changes
git commit -m "$COMMIT_MSG"

echo "✓ Configuration committed successfully!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git log -1 -p"
# Get configured hostname for rebuild command
CONFIG_HOST=$(grep "^hostname" system-settings.toml 2>/dev/null | sed '"'"'s/.*= *"\\(.*\\)".*/\\1/'"'"' | head -1)
CONFIG_HOST="${CONFIG_HOST:-nixoa}"
echo "  2. Rebuild NiXOA: cd /etc/nixos/nixoa/nixoa-vm && sudo nixos-rebuild switch --flake .#${CONFIG_HOST}"
echo ""
echo "To undo this commit: git reset HEAD~1
'
  run "cat > \"$SCRIPTS_DIR/commit-config.sh\" <<'EOF'
$COMMIT_SCRIPT_CONTENT
EOF"
fi

if [[ ! -f "$SCRIPTS_DIR/apply-config.sh" ]]; then
  echo "Adding apply-config.sh script..."
  APPLY_SCRIPT_CONTENT='#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Commit and apply configuration changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

# Get commit message from argument or use default
if [ $# -eq 0 ]; then
    COMMIT_MSG="Update configuration [$(date '"'"'+%Y-%m-%d %H:%M:%S'"'"')]"
else
    COMMIT_MSG="$1"
fi

# Commit the configuration
echo "=== Committing configuration changes ==="
"$SCRIPT_DIR/commit-config.sh" "$COMMIT_MSG"

# Apply the configuration
echo ""
echo "=== Applying configuration to NiXOA ==="
cd /etc/nixos/nixoa/nixoa-vm

# Read hostname from user-config (defaults to "nixoa" if not set)
HOSTNAME=$(grep "^hostname" "$CONFIG_DIR/system-settings.toml" 2>/dev/null | sed '"'"'s/.*= *"\\(.*\\)".*/\\1/'"'"' | head -1)
HOSTNAME="${HOSTNAME:-nixoa}"

echo "Running: sudo nixos-rebuild switch --flake .#${HOSTNAME}"
sudo nixos-rebuild switch --flake ".#${HOSTNAME}"

echo ""
echo "✓ Configuration applied successfully!"
'
  run "cat > \"$SCRIPTS_DIR/apply-config.sh\" <<'EOF'
$APPLY_SCRIPT_CONTENT
EOF"
fi

# Make sure scripts are executable
run "chmod +x \"$SCRIPTS_DIR\"/*.sh || true"

# 5. Copy hardware-configuration.nix into user config
SRC_HW="/etc/nixos/hardware-configuration.nix"
DEST_HW="$USER_REPO_DIR/hardware-configuration.nix"
if [[ -f "$SRC_HW" ]]; then
  echo "Copying hardware-configuration.nix to user config..."
  run "sudo cp \"$SRC_HW\" \"$DEST_HW\""
  run "sudo chown $USER:$USER \"$DEST_HW\""
else
  echo "Generating hardware-configuration.nix..."
  run "sudo nixos-generate-config --show-hardware-config > \"$DEST_HW\""
  run "sudo chown $USER:$USER \"$DEST_HW\""
fi

# 6. Git commit initial user config
echo "Committing initial files in user-config repo..."
run "git -C \"$USER_REPO_DIR\" add -A"
run "git -C \"$USER_REPO_DIR\" commit -m \"Initial NiXOA configuration\" || true"

# 7. Create symlink for flake input
echo "Creating symlink for flake input..."
run "sudo ln -sf \"$USER_REPO_DIR\" \"$BASE_DIR/user-config\""

# 8. Prompt user to edit configuration before first rebuild
echo ""
echo "================================"
echo "Initial Setup Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Edit your configuration in your user-config:"
echo "   nano $USER_REPO_DIR/system-settings.toml"
echo ""
echo "2. Add your SSH public key(s) to the sshKeys array (REQUIRED)"
echo ""
echo "3. Set hostname, admin username, and other settings as needed"
echo ""
echo "4. Apply your configuration:"
echo "   cd $USER_REPO_DIR"
echo "   ./scripts/apply-config.sh \"Initial deployment\""
echo ""
echo "Or manually:"
echo "   cd /etc/nixos/nixoa/nixoa-vm"
echo "   sudo nixos-rebuild switch --flake .#<hostname>"
echo ""
echo "For more information, see:"
echo "  - $USER_REPO_DIR/README.md"
echo "  - $BASE_DIR/nixoa-vm/README.md"
echo "  - $BASE_DIR/nixoa-vm/CONFIGURATION.md"
echo ""
