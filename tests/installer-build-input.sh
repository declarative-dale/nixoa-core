#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
: "${NIXOA_CI:?NIXOA_CI must point to the packaged automation CLI}"

fixture=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-build-input.XXXXXX")
trap 'rm -rf -- "${fixture}"' EXIT

mkdir -p \
  "${fixture}/.github/workflows" \
  "${fixture}/docs" \
  "${fixture}/modules/outputs" \
  "${fixture}/nix/automation" \
  "${fixture}/packer" \
  "${fixture}/tests"
printf '%s\n' '#!/usr/bin/env bash' 'printf build' \
  >"${fixture}/nix/automation/installer-build-assets.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf boot' \
  >"${fixture}/nix/automation/installer-boot.sh"
printf '%s\n' '# automation fixture' \
  >"${fixture}/nix/automation/default.nix"
printf '%s\n' '{ "installer": { "targets": [] } }' \
  >"${fixture}/nix/ci-plans.json"
printf '%s\n' 'workflow: installer' \
  >"${fixture}/.github/workflows/ci.yml"
printf '%s\n' '{ outputs = {}; }' >"${fixture}/flake.nix"
printf '%s\n' '{ "nodes": {}, "root": "root", "version": 7 }' \
  >"${fixture}/flake.lock"
printf '%s\n' '{ config.system.stateVersion = "26.05"; }' \
  >"${fixture}/modules/appliance.nix"
printf '%s\n' '{ flake.devShells = {}; }' \
  >"${fixture}/modules/outputs/dev-shells.nix"
printf '%s\n' '{ flake.checks = {}; }' \
  >"${fixture}/modules/outputs/checks.nix"
printf '%s\n' '# Contributor notes' >"${fixture}/docs/notes.md"
printf '%s\n' '2.0.1-dev.0' >"${fixture}/VERSION"
printf '%s\n' '[project]' 'name = "fixture"' 'revision = "1.0"' \
  >"${fixture}/secretspec.toml"
printf '%s\n' '#!/usr/bin/env bash' >"${fixture}/tests/example.sh"
printf '%s\n' 'packer fixture' >"${fixture}/packer/example.pkr.hcl"

git -C "${fixture}" init -q
git -C "${fixture}" add .
baseline=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${baseline}" =~ ^[0-9a-f]{64}$ ]]

printf '%s\n' '# Updated contributor notes' >"${fixture}/docs/notes.md"
printf '%s\n' '2.0.2-dev.0' >"${fixture}/VERSION"
printf '%s\n' '#!/usr/bin/env bash' 'printf test' \
  >"${fixture}/tests/example.sh"
printf '%s\n' 'updated packer fixture' >"${fixture}/packer/example.pkr.hcl"
printf '%s\n' '{ flake.devShells = { updated = true; }; }' \
  >"${fixture}/modules/outputs/dev-shells.nix"
printf '%s\n' '{ flake.checks = { updated = true; }; }' \
  >"${fixture}/modules/outputs/checks.nix"
printf '%s\n' '# repository cache contract' \
  >>"${fixture}/secretspec.toml"
git -C "${fixture}" add .
metadata_only=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${metadata_only}" == "${baseline}" ]] || {
  printf 'Metadata-only fixture unexpectedly changed installer state.\n' >&2
  exit 1
}

printf '%s\n' 'workflow: updated installer runner' \
  >"${fixture}/.github/workflows/ci.yml"
git -C "${fixture}" add .github/workflows/ci.yml
workflow_change=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${workflow_change}" != "${baseline}" ]] || {
  printf 'CI workflow fixture did not change installer state.\n' >&2
  exit 1
}

printf '%s\n' '{ config.system.stateVersion = "26.11"; }' \
  >"${fixture}/modules/appliance.nix"
git -C "${fixture}" add modules/appliance.nix
appliance_change=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${appliance_change}" != "${baseline}" ]] || {
  printf 'Appliance fixture did not change installer state.\n' >&2
  exit 1
}

printf '%s\n' '#!/usr/bin/env bash' 'printf updated-build' \
  >"${fixture}/nix/automation/installer-build-assets.sh"
git -C "${fixture}" add nix/automation/installer-build-assets.sh
recipe_change=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${recipe_change}" != "${appliance_change}" ]] || {
  printf 'Artifact recipe fixture did not change installer state.\n' >&2
  exit 1
}

printf '%s\n' '# automation policy changed' >>"${fixture}/nix/automation/default.nix"
git -C "${fixture}" add nix/automation/default.nix
automation_change=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${automation_change}" != "${recipe_change}" ]] || {
  printf 'Nix automation fixture did not change installer state.\n' >&2
  exit 1
}

printf '%s\n' '{ "installer": { "targets": ["changed"] } }' \
  >"${fixture}/nix/ci-plans.json"
git -C "${fixture}" add nix/ci-plans.json
plan_change=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
[[ "${plan_change}" != "${automation_change}" ]] || {
  printf 'CI plan fixture did not change installer state.\n' >&2
  exit 1
}

printf 'Installer build-input fixture checks passed.\n'
