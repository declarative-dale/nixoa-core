#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# NiXOA Bootstrap Installer
# This script bootstraps the NiXOA base flake and user configuration flake.
# It is idempotent and can be run multiple times safely.

set -euo pipefail

# Configuration
BASE_DIR="/etc/nixos"                                # Target location for base flake (nixoa-vm)
BASE_REPO="https://codeberg.org/nixoa/nixoa-vm.git"
USER_REPO_DIR="$HOME/user-config"                   # Target location for user config flake (user home directory)
USER_REPO_REMOTE="https://codeberg.org/nixoa/user-config.git"
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

# 1. Clone base flake (nixoa-vm) to /etc/nixos/nixoa-vm
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

# 3. Set up user config flake repository
if [[ -d "$USER_REPO_DIR" ]]; then
  echo "User config directory $USER_REPO_DIR already exists."
  if [[ -d "$USER_REPO_DIR/.git" ]]; then
    echo " - Git repository detected for user config."
  else
    echo " - Note: $USER_REPO_DIR exists but is not a git repo."
  fi
else
  echo "Cloning user config flake to $USER_REPO_DIR ..."
  run "sudo git clone $USER_REPO_REMOTE $USER_REPO_DIR"
fi

# 4. Populate user config flake with initial files (if not already present from git)
# User-config is now a full flake in git, but we'll populate missing config files

# a) configuration.nix (pure Nix configuration)
if [[ ! -f "$USER_REPO_DIR/configuration.nix" ]]; then
  echo "Writing configuration.nix..."
  CONFIG_NIX_CONTENT='# SPDX-License-Identifier: Apache-2.0
# NiXOA User Configuration
# Pure Nix configuration with userSettings and systemSettings

{ lib, pkgs, ... }:

{
  # ========================================================================
  # USER SETTINGS (Home Manager, extra packages, etc.)
  # ========================================================================

  userSettings = {
    # User-specific packages managed by Home Manager
    packages.extra = [
      # Add your user packages here, e.g.:
      # "neovim"
      # "tmux"
      # "lazygit"
    ];

    # Enable terminal enhancements (zsh, oh-my-posh, enhanced tools, etc.)
    extras.enable = false;
  };

  # ========================================================================
  # SYSTEM SETTINGS (XO configuration, networking, storage, etc.)
  # ========================================================================

  systemSettings = {
    # Basic system identification
    hostname = "nixoa";
    username = "xoa";
    stateVersion = "25.11";
    timezone = "UTC";

    # SSH access (REQUIRED)
    sshKeys = [
      # Add your SSH public keys here, e.g.:
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@laptop"
    ];

    # Xen Orchestra service account
    xo = {
      service = {
        user = "xo";
        group = "xo";
      };
      host = "0.0.0.0";
      port = 80;
      httpsPort = 443;

      # TLS/HTTPS configuration
      tls = {
        enable = true;
        redirectToHttps = true;
        autoGenerate = true;  # Auto-generate self-signed certificates
        dir = "/etc/ssl/xo";
        cert = "/etc/ssl/xo/certificate.pem";
        key = "/etc/ssl/xo/key.pem";
      };
    };

    # Remote storage support
    storage = {
      nfs.enable = true;
      cifs.enable = true;
      vhd.enable = true;
      mountsDir = "/var/lib/xo/mounts";
    };

    # Networking and firewall
    networking.firewall.allowedTCPPorts = [ 80 443 3389 5900 8012 ];

    # System packages to install globally
    packages.system.extra = [
      # Add system packages here, e.g.:
      # "neovim"
      # "htop"
    ];

    # Automated updates configuration
    updates = {
      # Configure automatic updates here if desired
    };

    # Custom services
    services.definitions = {};
  };
}
'
  run "cat > \"$USER_REPO_DIR/configuration.nix\" <<'EOF'
$CONFIG_NIX_CONTENT
EOF"
fi

# c) config.nixoa.toml (XO server configuration)
if [[ ! -f "$USER_REPO_DIR/config.nixoa.toml" ]]; then
  echo "Creating initial config.nixoa.toml..."
  XO_CONFIG_CONTENT='# SPDX-License-Identifier: Apache-2.0
# XO Server Configuration
# Optional: Customize XO server settings here

# Example authentication settings (uncomment to use):
# [authentication]
# defaultTokenValidity = "30 days"

# Example mail settings for alerts:
# [mail]
# from = "xo@example.com"
# transport = "smtp://smtp.example.com:587"

# Example logging:
# [logs]
# level = "info"  # trace, debug, info, warn, error
'
  run "cat > \"$USER_REPO_DIR/config.nixoa.toml\" <<'EOF'
$XO_CONFIG_CONTENT
EOF"
fi

# d) scripts directory
SCRIPTS_DIR="$USER_REPO_DIR/scripts"
run "mkdir -p \"$SCRIPTS_DIR\""

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
git diff --stat configuration.nix config.nixoa.toml 2>/dev/null || true
echo ""

# Check if there are changes to commit
if git diff --quiet configuration.nix config.nixoa.toml 2>/dev/null; then
    echo "No changes to commit."
    exit 0
fi

# Commit the changes (auto-stages tracked files)
git commit -a -m "$COMMIT_MSG"

echo "✓ Configuration committed successfully!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git log -1 -p"
# Get configured hostname for rebuild command
CONFIG_HOST=$(grep "hostname = " configuration.nix 2>/dev/null | sed '"'"'s/.*= *"\\(.*\\)".*/\\1/'"'"' | head -1)
CONFIG_HOST="${CONFIG_HOST:-nixoa}"
echo "  2. Rebuild NiXOA: cd ~/user-config && sudo nixos-rebuild switch --flake .#${CONFIG_HOST}"
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

# Apply the configuration from user-config directory
echo ""
echo "=== Applying configuration to NiXOA ==="
cd "$CONFIG_DIR"

# Read hostname from user-config (defaults to "nixoa" if not set)
HOSTNAME=$(grep "hostname = " "$CONFIG_DIR/configuration.nix" 2>/dev/null | sed '"'"'s/.*= *"\\(.*\\)".*/\\1/'"'"' | head -1)
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

# 7. Prompt user to edit configuration before first rebuild
echo ""
echo "================================"
echo "Initial Setup Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Edit your configuration in your user-config:"
echo "   nano $USER_REPO_DIR/configuration.nix"
echo ""
echo "2. Add your SSH public key(s) to systemSettings.sshKeys (REQUIRED)"
echo ""
echo "3. Set hostname, username, and other settings in systemSettings"
echo ""
echo "4. (Optional) Customize XO server settings in config.nixoa.toml"
echo ""
echo "5. Apply your configuration:"
echo "   cd $USER_REPO_DIR"
echo "   ./scripts/apply-config.sh \"Initial deployment\""
echo ""
echo "Or manually:"
echo "   cd ~/user-config"
echo "   sudo nixos-rebuild switch --flake .#<hostname>"
echo ""
echo "For more information, see:"
echo "  - $USER_REPO_DIR/README.md"
echo "  - $BASE_DIR/nixoa-vm/README.md"
echo ""
