#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# NiXOA Bootstrap Installer
# This script bootstraps the NiXOA system configuration flake.
# It is idempotent and can be run multiple times safely.

set -euo pipefail

# Configuration
USER_REPO_DIR="$HOME/system"                   # Target location for system config flake (user home directory)
USER_REPO_REMOTE="https://codeberg.org/NiXOA/system.git"
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

# 1. Prompt for git user info if not set
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

# 2. Set up system config flake repository
if [[ -d "$USER_REPO_DIR" ]]; then
  echo "User config directory $USER_REPO_DIR already exists."
  if [[ -d "$USER_REPO_DIR/.git" ]]; then
    echo " - Git repository detected for system config."
  else
    echo " - Note: $USER_REPO_DIR exists but is not a git repo."
  fi
else
  echo "Cloning system config flake to $USER_REPO_DIR ..."
  run "git clone $USER_REPO_REMOTE $USER_REPO_DIR"
fi

# 3. Populate system config flake with initial files (if not already present from git)
# System config is now a full flake in git, but we'll populate missing config files

# a) configuration.nix (should already exist in the system repo)
if [[ ! -f "$USER_REPO_DIR/configuration.nix" ]]; then
  echo "configuration.nix is missing. Please restore it from the system repo."
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
git diff --stat configuration.nix config config.nixoa.toml 2>/dev/null || true
echo ""

# Check if there are changes to commit
if git diff --quiet configuration.nix config config.nixoa.toml 2>/dev/null; then
    echo "No changes to commit."
    exit 0
fi

# Stage configuration files (including config fragments)
git add configuration.nix config config.nixoa.toml

# Commit the changes
git commit -m "$COMMIT_MSG"

echo "✓ Configuration committed successfully!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git log -1 -p"
# Get configured hostname for rebuild command
CONFIG_HOST=$(grep "hostname = " config/identity.nix 2>/dev/null | sed '"'"'s/.*= *"\\(.*\\)".*/\\1/'"'"' | head -1)
CONFIG_HOST="${CONFIG_HOST:-nixoa}"
echo "  2. Rebuild NiXOA: cd ~/system && sudo nixos-rebuild switch --flake .#${CONFIG_HOST}"
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

# Apply the configuration from system config directory
echo ""
echo "=== Applying configuration to NiXOA ==="
cd "$CONFIG_DIR"

# Read hostname from system config (defaults to "nixoa" if not set)
HOSTNAME=$(grep "hostname = " "$CONFIG_DIR/config/identity.nix" 2>/dev/null | sed '"'"'s/.*= *"\\(.*\\)".*/\\1/'"'"' | head -1)
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

# 4. Copy hardware-configuration.nix into system config
SRC_HW="/etc/nixos/hardware-configuration.nix"
DEST_HW="$USER_REPO_DIR/hardware-configuration.nix"
if [[ -f "$SRC_HW" ]]; then
  echo "Copying hardware-configuration.nix to system config..."
  run "sudo cp \"$SRC_HW\" \"$DEST_HW\""
  run "sudo chown $USER:$USER \"$DEST_HW\""
else
  echo "Generating hardware-configuration.nix..."
  run "sudo nixos-generate-config --show-hardware-config > \"$DEST_HW\""
  run "sudo chown $USER:$USER \"$DEST_HW\""
fi

# 5. Git commit initial system config
echo "Committing initial files in system config repo..."
run "git -C \"$USER_REPO_DIR\" add -A"
run "git -C \"$USER_REPO_DIR\" commit -m \"Initial NiXOA configuration\" || true"

# 6. Prompt user to edit configuration before first rebuild
echo ""
echo "================================"
echo "Initial Setup Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Edit your configuration:"
echo "   nano $USER_REPO_DIR/config/identity.nix"
echo ""
echo "2. Add your SSH public key(s) to sshKeys (REQUIRED)"
echo ""
echo "3. Set hostname, username, and other settings in config/"
echo ""
echo "4. (Optional) Customize XO server settings in config.nixoa.toml"
echo ""
echo "5. Apply your configuration:"
echo "   cd $USER_REPO_DIR"
echo "   ./scripts/apply-config.sh \"Initial deployment\""
echo ""
echo "Or manually:"
echo "   cd ~/system"
echo "   sudo nixos-rebuild switch --flake .#<hostname>"
echo ""
echo "For more information, see:"
echo "  - $USER_REPO_DIR/README.md"
echo ""
