#!/usr/bin/env bash
set -euo pipefail
HOST=$(jq -r '.hostname' vars.nix 2>/dev/null || sed -n 's/hostname *= *"\(.*\)".*/\1/p' vars.nix | head -1)
: "${HOST:?hostname not found in vars.nix}"
sudo nixos-rebuild switch --flake .#"${HOST}" -L --show-trace
