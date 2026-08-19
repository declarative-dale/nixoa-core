#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_root=${NIXOA_SYSTEM_ROOT:-}
if [[ -z "$repo_root" ]]; then
  repo_root=$(git rev-parse --show-toplevel)
fi
policy=${NIXOA_INSTALLER_POLICY:-$repo_root/nix/automation/installer-policy.json}

jq -e '
  (.buildInputPaths | type == "array") and
  (.buildInputPaths | length > 0) and
  all(.buildInputPaths[]; type == "string" and length > 0)
' "$policy" >/dev/null
mapfile -t build_input_paths < <(jq -r '.buildInputPaths[]' "$policy")

{
  printf '%s\0' 'nixoa-installer-state-v3'
  git -C "$repo_root" ls-files -s -z -- "${build_input_paths[@]}"
} | sha256sum | cut -d' ' -f1
