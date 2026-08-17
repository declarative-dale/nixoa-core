#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-release-assets.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

printf '0123456789abcdefghijklmno' >"$temporary/installer.iso"
NIXOA_RELEASE_PART_SIZE=10 \
NIXOA_RELEASE_ASSET_LIMIT=12 \
  bash "$test_root/ci/stage-release-installer.sh" \
    "$temporary/installer.iso" \
    "$temporary/versioned/nixoa-v1.1.1.iso" \
    "$temporary/release"

mapfile -t parts < <(find "$temporary/release" -name '*.iso.part-*' -print | sort)
[[ ${#parts[@]} -eq 3 ]]
cat "${parts[@]}" >"$temporary/reconstructed.iso"
cmp "$temporary/installer.iso" "$temporary/reconstructed.iso"
(
  cd "$temporary/versioned"
  sha256sum --check --strict "$temporary/release/nixoa-v1.1.1.iso.sha256"
)

printf 'Release asset fixture checks passed.\n'
