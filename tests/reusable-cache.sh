#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-reusable-cache.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

workspace="$temporary/workspace"
fake_store="$temporary/nix/store"
cache_dir="$temporary/cache"
install -d "$workspace" "$fake_store" "$temporary/bin"

names=(deploy-template metadata nixoa-menu nxcli)
for index in "${!names[@]}"; do
  hash=$(printf '%032d' "$((index + 1))")
  store_path="$fake_store/${hash}-${names[$index]}"
  install -d "$store_path"
  ln -s "$store_path" "$workspace/result-${names[$index]}"
done

# The variable reference belongs in the generated fixture.
# shellcheck disable=SC2016
printf '%s\n' \
  "#!${BASH}" \
  'printf "%s\n" "$*" >>"$FAKE_NIX_LOG"' \
  'exit 0' \
  >"$temporary/bin/nix"
chmod +x "$temporary/bin/nix"

  FAKE_NIX_LOG="$temporary/nix.log" \
  NIX_BIN="$temporary/bin/nix" \
  NIX_STORE_DIR="$fake_store" \
  NIXOA_WORKSPACE="$workspace" \
  bash "$test_root/ci/reusable-cache.sh" export "$cache_dir"

jq -e '
  .schema_version == 1 and
  ([.roots[].name] | sort == ["deploy-template", "metadata", "nixoa-menu", "nxcli"]) and
  (.roots | length == 4)
' "$cache_dir/nixoa-roots.json" >/dev/null
grep -Fq "copy --to file://${cache_dir}" "$temporary/nix.log"

FAKE_NIX_LOG="$temporary/nix.log" \
  NIX_BIN="$temporary/bin/nix" \
  NIX_STORE_DIR="$fake_store" \
  bash "$test_root/ci/reusable-cache.sh" restore "$cache_dir"
grep -Fq "copy --no-check-sigs --from file://${cache_dir}" "$temporary/nix.log"

jq '.roots += [{name:"unexpected",store_path:"/nix/store/00000000000000000000000000000000-unexpected"}]' \
  "$cache_dir/nixoa-roots.json" >"$temporary/invalid-roots.json"
mv "$temporary/invalid-roots.json" "$cache_dir/nixoa-roots.json"
if FAKE_NIX_LOG="$temporary/nix.log" \
  NIX_BIN="$temporary/bin/nix" \
  NIX_STORE_DIR="$fake_store" \
  bash "$test_root/ci/reusable-cache.sh" restore "$cache_dir" >/dev/null 2>&1; then
  printf 'Reusable cache accepted an unexpected root.\n' >&2
  exit 1
fi

printf 'Reusable cache fixture checks passed.\n'
