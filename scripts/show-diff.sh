#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Show uncommitted NiXOA repository changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
nixoa_require_git_repo
nixoa_cd_root

echo "=== Uncommitted Changes ==="
git diff HEAD -- "${NIXOA_TRACKED_PATHS[@]}"
echo ""
echo "=== Git Status ==="
nixoa_status_porcelain || true

if [ -z "$(nixoa_status_porcelain)" ]; then
  echo "No uncommitted changes."
fi
