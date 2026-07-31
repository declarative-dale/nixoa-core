#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_url=${NIXOA_REPO_URL:-https://github.com/declarative-dale/nixoa-core.git}
repo_branch=${NIXOA_REPO_BRANCH:-main}

exec sudo -n install-nixoa \
  --yes \
  --operator-key /tmp/nixoa-operator.pub \
  --repo-url "$repo_url" \
  --branch "$repo_branch"
