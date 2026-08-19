#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_root=${NIXOA_SYSTEM_ROOT:-}
if [[ -z "$repo_root" ]]; then
  repo_root=$(git rev-parse --show-toplevel)
fi
policy=${NIXOA_INSTALLER_POLICY:-$repo_root/nix/automation/installer-policy.json}

jq -e '
  (.ignoredChangePatterns | type == "array") and
  all(.ignoredChangePatterns[]; type == "string" and length > 0)
' "$policy" >/dev/null
mapfile -t ignored_patterns < <(jq -r '.ignoredChangePatterns[]' "$policy")

required=false
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if [[ "$path" == .github/workflows/ci.yml ]]; then
    required=true
    break
  fi

  ignored=false
  for pattern in "${ignored_patterns[@]}"; do
    # Policy entries are intentionally interpreted as shell glob patterns.
    # shellcheck disable=SC2053
    if [[ "$path" == $pattern ]]; then
      ignored=true
      break
    fi
  done
  if [[ "$ignored" == false ]]; then
    required=true
    break
  fi
done
printf '%s\n' "$required"
