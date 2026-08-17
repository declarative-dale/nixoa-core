#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "${script_dir}" rev-parse --show-toplevel)

# Hash the Git index rather than a commit so metadata and CI-maintenance commits
# can reuse the exact tested artifact. Modes, blob IDs, and paths are all part
# of the state. Edit this script whenever the artifact recipe itself changes.
{
  printf '%s\0' 'nixoa-installer-state-v2'
  git -C "${repo_root}" ls-files -s -z -- \
    .github/workflows/ci.yml \
    ci/boot-installer-iso.sh \
    ci/build-release-assets.sh \
    ci/installer-build-input.sh \
    ci/reusable-cache.sh \
    flake.lock \
    flake.nix \
    host \
    installer \
    modules \
    ':(exclude)modules/outputs/checks.nix' \
    ':(exclude)modules/outputs/dev-shells.nix' \
    pkgs \
    scripts
} \
  | sha256sum \
  | cut -d' ' -f1
