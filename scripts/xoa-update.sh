#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null; then
  echo "jq is required"; exit 1
fi

OLD=$(jq -r '.nodes.xoSrc.locked.rev // empty' flake.lock 2>/dev/null || true)

echo "Updating xoSrc input..."
nix flake lock --update-input xoSrc --commit-lock-file

NEW=$(jq -r '.nodes.xoSrc.locked.rev // empty' flake.lock)
if [[ -z "$NEW" ]]; then
  echo "Could not read new rev from flake.lock"; exit 1
fi

echo "xoSrc: ${OLD:-<none>} -> ${NEW}"

# Show commit messages if possible
if [[ -n "${OLD}" && "${OLD}" != "${NEW}" ]]; then
  echo
  echo "Attempting to show commit messages between ${OLD}..${NEW} (best effort):"
  TMP=$(mktemp -d)
  git clone --depth 1 https://github.com/vatesfr/xen-orchestra.git "$TMP" >/dev/null 2>&1 || true
  if git -C "$TMP" fetch --depth 100 origin "${NEW}" >/dev/null 2>&1 && git -C "$TMP" fetch --depth 100 origin "${OLD}" >/dev/null 2>&1; then
    git -C "$TMP" log --oneline "${OLD}..${NEW}" || true
  else
    echo "(Tip: set GITHUB_TOKEN and use: curl -H \"Authorization: token \$GITHUB_TOKEN\" https://api.github.com/repos/vatesfr/xen-orchestra/compare/${OLD}...${NEW})"
  fi
  rm -rf "$TMP"
fi

echo
echo "Done. Rebuild with:"
echo "  sudo nixos-rebuild switch --flake .#$(jq -r '.hostname' vars.nix)"
