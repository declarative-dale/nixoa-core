#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if ! command -v jq >/dev/null; then
  echo "jq is required"; exit 1
fi

OLD=$(jq -r '.nodes."xen-orchestra-ce".locked.rev // empty' flake.lock 2>/dev/null || true)

echo "Updating xen-orchestra-ce input..."
nix flake lock --update-input xen-orchestra-ce --commit-lock-file

NEW=$(jq -r '.nodes."xen-orchestra-ce".locked.rev // empty' flake.lock)
if [[ -z "$NEW" ]]; then
  echo "Could not read new rev from flake.lock"; exit 1
fi

echo "xen-orchestra-ce: ${OLD:-<none>} -> ${NEW}"

# Show commit messages if possible
if [[ -n "${OLD}" && "${OLD}" != "${NEW}" ]]; then
  echo
  echo "Attempting to show commit messages between ${OLD}..${NEW} (best effort):"
  TMP=$(mktemp -d)
  git clone --depth 1 https://codeberg.org/NiXOA/xen-orchestra-ce.git "$TMP" >/dev/null 2>&1 || true
  if git -C "$TMP" fetch --depth 100 origin "${NEW}" >/dev/null 2>&1 && git -C "$TMP" fetch --depth 100 origin "${OLD}" >/dev/null 2>&1; then
    git -C "$TMP" log --oneline "${OLD}..${NEW}" || true
  else
    echo "(Tip: ensure you can reach codeberg.org and that the refs exist.)"
  fi
  rm -rf "$TMP"
fi

echo
echo "Done. Rebuild with:"

# Resolve config directory with proper sudo handling
if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    CONFIG_DIR="${REAL_HOME}/user-config"
else
    CONFIG_DIR="${HOME}/user-config"
fi

# Get configured hostname for the rebuild command
CONFIG_HOST=$(grep "hostname = " "${CONFIG_DIR}/configuration.nix" 2>/dev/null | sed 's/.*= *"\(.*\)".*/\1/' | head -1)
CONFIG_HOST="${CONFIG_HOST:-nixoa}"
echo "  sudo nixos-rebuild switch --flake .#${CONFIG_HOST}"
