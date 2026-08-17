#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-ci-helpers.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

[[ $(printf '%s\n' README.md docs/ci.md VERSION packer/build.sh modules/outputs/dev-shells.nix ci/installer-changes.sh ci/release-notes.sh ci/stage-release-installer.sh | bash "$test_root/ci/installer-changes.sh") == false ]]
[[ $(printf '%s\n' modules/_nixos/platform.nix | bash "$test_root/ci/installer-changes.sh") == true ]]
[[ $(printf '%s\n' ci/build-release-assets.sh | bash "$test_root/ci/installer-changes.sh") == true ]]
[[ $(printf '%s\n' .github/workflows/ci.yml | bash "$test_root/ci/installer-changes.sh") == true ]]
[[ $(printf '%s\n' ci/github/main-ruleset.json | bash "$test_root/ci/installer-changes.sh") == false ]]
[[ $(printf '%s\n' future/unknown-output | bash "$test_root/ci/installer-changes.sh") == true ]]

read -r version bump < <(printf '%s\n' 'fix: correction' | bash "$test_root/ci/release-version.sh" 2.0.0 auto)
[[ "$version $bump" == '2.0.1 patch' ]]
read -r version bump < <(printf '%s\n' 'fix: correction' | bash "$test_root/ci/release-version.sh" 1.0 auto)
[[ "$version $bump" == '1.0.1 patch' ]]
read -r version bump < <(printf '%s\n' 'feat(core): capability' | bash "$test_root/ci/release-version.sh" 2.0.0 auto)
[[ "$version $bump" == '2.1.0 minor' ]]

jq -e '
  .enforcement == "active" and
  (.bypass_actors | length) == 0 and
  ([.rules[].type] | index("merge_queue") | not) and
  any(.rules[]; .type == "required_status_checks" and .parameters.strict_required_status_checks_policy == true and .parameters.required_status_checks == [{context:"CI gate",integration_id:15368}])
' "$test_root/ci/github/main-ruleset.json" >/dev/null
read -r version bump < <(printf '%s\n' 'feat!: incompatible' | bash "$test_root/ci/release-version.sh" 2.0.0 auto)
[[ "$version $bump" == '3.0.0 major' ]]
read -r version bump < <(printf '%s\n' 'fix: correction' | bash "$test_root/ci/release-version.sh" 2.0.0 minor)
[[ "$version $bump" == '2.1.0 minor' ]]

release_notes=$(bash "$test_root/ci/release-notes.sh" 1.1.0 "$test_root/CHANGELOG.md")
grep -Fq 'Security' <<<"$release_notes"
grep -Fq 'Magic Cache' <<<"$release_notes"
if grep -Fq 'Unreleased' <<<"$release_notes"; then
  printf 'Release notes include the Unreleased section.\n' >&2
  exit 1
fi
if bash "$test_root/ci/release-notes.sh" 9.9.9 "$test_root/CHANGELOG.md" >/dev/null 2>&1; then
  printf 'Release notes accepted a missing version.\n' >&2
  exit 1
fi

grep -Fq 'gh release view --json tagName --jq .tagName' \
  "$test_root/.github/workflows/release.yml"
if grep -Fq "git tag --list 'v[0-9]*.[0-9]*.[0-9]*'" \
  "$test_root/.github/workflows/release.yml"; then
  printf 'Release automation still derives its baseline from unpublished tags.\n' >&2
  exit 1
fi

mkdir -p "$temporary/bin"
printf 'fixture iso\n' >"$temporary/installer.iso"
cat >"$temporary/bin/qemu-img" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$temporary/bin/qemu-system-x86_64" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM
printf 'nixoa-installer login:\n'
sleep 30
EOF
sed -i "1c#!${BASH}" \
  "$temporary/bin/qemu-img" \
  "$temporary/bin/qemu-system-x86_64"
chmod +x "$temporary/bin/qemu-img" "$temporary/bin/qemu-system-x86_64"
PATH="$temporary/bin:$PATH" \
  BOOT_TIMEOUT=20s \
  BOOT_LOG="$temporary/boot.log" \
  timeout 5s bash "$test_root/ci/boot-installer-iso.sh" "$temporary/installer.iso"
grep -Fq 'nixoa-installer login:' "$temporary/boot.log"

cat >"$temporary/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == 'pr view' ]]; then
  jq -n \
    --arg author "${FAKE_AUTHOR:-github-actions[bot]}" \
    '{author:{login:$author},baseRefName:"main",headRefName:"automation/test",headRefOid:"abc123",headRepository:{nameWithOwner:"example/core"},mergeStateStatus:"CLEAN",state:"OPEN",title:"Trusted update",url:"https://example.invalid/pr/1"}'
elif [[ "$1 $2" == 'run list' ]]; then
  printf '42\n'
elif [[ "$1 $2" == 'run watch' ]]; then
  exit 0
elif [[ "$1 $2" == 'pr merge' ]]; then
  printf '%s\n' "$*" >"$FAKE_MERGE_LOG"
else
  printf 'unexpected gh call: %s\n' "$*" >&2
  exit 1
fi
EOF
sed -i "1c#!${BASH}" "$temporary/bin/gh"
chmod +x "$temporary/bin/gh"
trusted_env=(
  GH_TOKEN=fixture
  GITHUB_REPOSITORY=example/core
  PR_NUMBER=1
  EXPECTED_BRANCH=automation/test
  EXPECTED_TITLE='Trusted update'
  EXPECTED_AUTHOR='github-actions[bot]'
  DEFAULT_BRANCH=main
  FAKE_MERGE_LOG="$temporary/merge.log"
)
env PATH="$temporary/bin:$PATH" "${trusted_env[@]}" \
  bash "$test_root/ci/trusted-update.sh"
grep -Fq -- '--match-head-commit abc123' "$temporary/merge.log"
if env PATH="$temporary/bin:$PATH" FAKE_AUTHOR=attacker "${trusted_env[@]}" \
  bash "$test_root/ci/trusted-update.sh" >/dev/null 2>&1; then
  printf 'Trusted update accepted the wrong author.\n' >&2
  exit 1
fi

printf 'CI helper fixture checks passed.\n'
