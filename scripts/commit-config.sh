#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Commit NiXOA repository changes to the local git repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
nixoa_require_git_repo
nixoa_cd_root

if [ "${1:-}" = "--help" ]; then
  echo "Usage: $0 [commit message]" >&2
  echo "If no message is supplied, the script prompts for one and auto-generates one when left blank." >&2
  exit 0
fi

COMMIT_MSG="${1:-}"

if ! nixoa_has_changes; then
  echo "No changes to commit."
  exit 0
fi

nixoa_print_change_summary
nixoa_stage_changes

if ! nixoa_has_staged_changes; then
  echo "No staged changes were produced."
  exit 0
fi

nixoa_commit_changes "$COMMIT_MSG"

echo "✓ Repository changes committed successfully!"
echo ""
echo "To undo this commit: git reset HEAD~1"
