#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Show NiXOA repository history for tracked paths

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
nixoa_require_git_repo
nixoa_cd_root

echo "=== NiXOA Repository History ==="
git log --oneline --decorate --graph -10 -- "${NIXOA_TRACKED_PATHS[@]}"

echo ""
echo "To see full diff for a commit: git show <commit-hash>"
echo "To restore paths from a commit: git restore --source <commit-hash> -- ${NIXOA_TRACKED_PATHS[*]}"
