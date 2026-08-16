#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-build-input.XXXXXX")
trap 'rm -rf -- "${fixture}"' EXIT

mkdir -p \
  "${fixture}/.github/workflows" \
  "${fixture}/ci" \
  "${fixture}/docs" \
  "${fixture}/modules" \
  "${fixture}/packer" \
  "${fixture}/tests"
cp "${test_root}/ci/installer-build-input.sh" \
  "${fixture}/ci/installer-build-input.sh"
printf '%s\n' 'workflow: installer' \
  >"${fixture}/.github/workflows/cache-nixoa-menu.yml"
printf '%s\n' '{ outputs = {}; }' >"${fixture}/flake.nix"
printf '%s\n' '{ "nodes": {}, "root": "root", "version": 7 }' \
  >"${fixture}/flake.lock"
printf '%s\n' '{ config.system.stateVersion = "26.05"; }' \
  >"${fixture}/modules/appliance.nix"
printf '%s\n' '# Contributor notes' >"${fixture}/docs/notes.md"
printf '%s\n' '2.0.1-dev.0' >"${fixture}/VERSION"
printf '%s\n' '#!/usr/bin/env bash' >"${fixture}/tests/example.sh"
printf '%s\n' 'packer fixture' >"${fixture}/packer/example.pkr.hcl"

git -C "${fixture}" init -q
git -C "${fixture}" add .
baseline=$(bash "${fixture}/ci/installer-build-input.sh")
[[ "${baseline}" =~ ^[0-9a-f]{64}$ ]]

printf '%s\n' '# Updated contributor notes' >"${fixture}/docs/notes.md"
printf '%s\n' '2.0.2-dev.0' >"${fixture}/VERSION"
printf '%s\n' '#!/usr/bin/env bash' 'printf test' \
  >"${fixture}/tests/example.sh"
printf '%s\n' 'updated packer fixture' >"${fixture}/packer/example.pkr.hcl"
printf '%s\n' 'workflow: updated installer runner' \
  >"${fixture}/.github/workflows/cache-nixoa-menu.yml"
git -C "${fixture}" add .
metadata_only=$(bash "${fixture}/ci/installer-build-input.sh")
[[ "${metadata_only}" == "${baseline}" ]] || {
  printf 'Metadata-only fixture unexpectedly changed installer state.\n' >&2
  exit 1
}

printf '%s\n' '{ config.system.stateVersion = "26.11"; }' \
  >"${fixture}/modules/appliance.nix"
git -C "${fixture}" add modules/appliance.nix
appliance_change=$(bash "${fixture}/ci/installer-build-input.sh")
[[ "${appliance_change}" != "${baseline}" ]] || {
  printf 'Appliance fixture did not change installer state.\n' >&2
  exit 1
}

printf 'Installer build-input fixture checks passed.\n'
