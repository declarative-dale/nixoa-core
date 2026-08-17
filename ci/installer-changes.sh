#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

required=false
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  case "$path" in
    AGENTS.md|LICENSE|VERSION|README*|CHANGELOG*|docs/*|packer/*|tests/*|modules/outputs/dev-shells.nix)
      ;;
    .github/workflows/ci.yml)
      required=true
      break
      ;;
    .github/*|ci/github/*|ci/release-notes.sh|ci/release-version.sh|ci/trusted-update.sh)
      ;;
    *)
      required=true
      break
      ;;
  esac
done

printf '%s\n' "$required"
