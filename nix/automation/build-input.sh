#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_root=${NIXOA_SYSTEM_ROOT:-}
if [[ -z "$repo_root" ]]; then
  repo_root=$(git rev-parse --show-toplevel)
fi
policy=${NIXOA_INSTALLER_POLICY:-$repo_root/nix/automation/installer-policy.json}

{
  printf '%s\0' 'nixoa-installer-state-v4'
  git -C "$repo_root" ls-files -s -z |
    NIXOA_INSTALLER_POLICY="$policy" nixoa-ci-classify-paths --filter-index
} | sha256sum | cut -d' ' -f1
