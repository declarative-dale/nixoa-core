#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
: "${NIXOA_CI:?NIXOA_CI must point to the packaged automation CLI}"
: "${NIXOA_SYSTEM_ROOT:?NIXOA_SYSTEM_ROOT must point to the source checkout}"

# The isolated release repository exercises the production installer-input
# policy without copying repository automation into the fixture.
export NIXOA_INSTALLER_POLICY="$NIXOA_SYSTEM_ROOT/nix/automation/installer-policy.json"

temporary=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-release-assets.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

printf '0123456789abcdefghijklmno' >"$temporary/installer.iso"
NIXOA_RELEASE_PART_SIZE=10 \
NIXOA_RELEASE_ASSET_LIMIT=12 \
  "$NIXOA_CI" release split \
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

# Exercise the combined inventory and release state machine in an isolated Git
# fixture, including the immutable build input and release manifest.
fixture="$temporary/release-state"
mkdir -p "$fixture/candidate/result-installer/iso" "$fixture/candidate-state"
printf '%s\n' '1.1.2' >"$fixture/VERSION"
printf 'fixture installer\n' >"$fixture/candidate/result-installer/iso/nixoa-installer.iso"
printf '%s\n' '{"spdxVersion":"SPDX-2.3"}' >"$fixture/candidate/nixoa-system.spdx.json"
printf '%s\n' '{"bomFormat":"CycloneDX"}' >"$fixture/candidate/nixoa-system.cdx.json"
git -C "$fixture" init -q
git -C "$fixture" add .
git -C "$fixture" -c user.name=fixture -c user.email=fixture@example.invalid \
  commit -qm fixture
source_sha=$(git -C "$fixture" rev-parse HEAD)
build_input=$(NIXOA_SYSTEM_ROOT="$fixture" "$NIXOA_CI" installer build-input)
jq -n \
  --arg build_input "$build_input" \
  --arg source_commit "$source_sha" \
  --arg artifact_source_commit "$source_sha" \
  '{schema_version:2,build_input:$build_input,source_commit:$source_commit,artifact_source_commit:$artifact_source_commit,producer_event:"push",artifact_run_id:42}' \
  >"$fixture/candidate-state/nixoa-build-state.json"

inventory_output="$temporary/inventory-output"
(
  cd "$fixture"
  GITHUB_OUTPUT="$inventory_output" \
    NIXOA_SYSTEM_ROOT="$fixture" \
    SOURCE_SHA="$source_sha" \
    "$NIXOA_CI" release inventory
)
grep -Fxq 'artifact_run_id=42' "$inventory_output"
grep -Fxq "build_input=${build_input}" "$inventory_output"

(
  cd "$fixture"
  ARTIFACT_RUN_ID=42 \
    ARTIFACT_SOURCE_COMMIT="$source_sha" \
    BUILD_INPUT="$build_input" \
    GITHUB_REPOSITORY=example/nixoa \
    GITHUB_RUN_ID=99 \
    NIXOA_RELEASE_ASSET_LIMIT=12 \
    NIXOA_RELEASE_PART_SIZE=10 \
    NIXOA_SYSTEM_ROOT="$fixture" \
    RELEASE_TAG=v1.1.2 \
    RELEASE_VERSION=1.1.2 \
    RUNNER_TEMP="$temporary" \
    SOURCE_SHA="$source_sha" \
    "$NIXOA_CI" release stage
)
jq -e \
  --arg build_input "$build_input" \
  --arg source_commit "$source_sha" '
    .schema_version == 2 and
    .version == "1.1.2" and
    .tag == "v1.1.2" and
    .build_input == $build_input and
    .source_commit == $source_commit and
    (.assets.installer.parts | length) > 1 and
    .assets.spdx.name == "nixoa-v1.1.2.spdx.json.gz" and
    .assets.cyclonedx.name == "nixoa-v1.1.2.cdx.json.gz"
  ' "$fixture/release/release-manifest.json" >/dev/null

printf 'Release asset fixture checks passed.\n'
