#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
: "${NIXOA_CI:?NIXOA_CI must point to the packaged automation CLI}"

test_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-ci-helpers.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

[[ $(printf '%s\n' README.md docs/ci.md VERSION packer/build.sh modules/outputs/checks.nix modules/outputs/dev-shells.nix nix/checks/repository-policy.nix | "$NIXOA_CI" classify-paths) == false ]]
[[ $(printf '%s\n' modules/_nixos/platform.nix | "$NIXOA_CI" classify-paths) == true ]]
[[ $(printf '%s\n' nix/automation/installer-build-assets.sh | "$NIXOA_CI" classify-paths) == true ]]
[[ $(printf '%s\n' .github/workflows/ci.yml | "$NIXOA_CI" classify-paths) == true ]]
[[ $(printf '%s\n' nix/automation/github/main-ruleset.json | "$NIXOA_CI" classify-paths) == false ]]
[[ $(printf '%s\n' future/unknown-output | "$NIXOA_CI" classify-paths) == true ]]

env CHECK_RESULT=success INSTALLER_REQUIRED=false PLAN_RESULT=skipped \
  BUILD_RESULT=skipped "$NIXOA_CI" gate
env CHECK_RESULT=success INSTALLER_REQUIRED=true PLAN_RESULT=success \
  SHOULD_BUILD=false BUILD_RESULT=skipped "$NIXOA_CI" gate
env CHECK_RESULT=success INSTALLER_REQUIRED=true PLAN_RESULT=success \
  SHOULD_BUILD=true BUILD_RESULT=success "$NIXOA_CI" gate
if env CHECK_RESULT=failure INSTALLER_REQUIRED=false PLAN_RESULT=skipped \
  BUILD_RESULT=skipped "$NIXOA_CI" gate; then
  printf 'CI gate accepted a failed repository check.\n' >&2
  exit 1
fi

read -r version bump < <(printf '%s\n' 'fix: correction' | "$NIXOA_CI" release version 2.0.0 auto)
[[ "$version $bump" == '2.0.1 patch' ]]
read -r version bump < <(printf '%s\n' 'fix: correction' | "$NIXOA_CI" release version 1.0 auto)
[[ "$version $bump" == '1.0.1 patch' ]]
read -r version bump < <(printf '%s\n' 'feat(core): capability' | "$NIXOA_CI" release version 2.0.0 auto)
[[ "$version $bump" == '2.1.0 minor' ]]

jq -e '
  .enforcement == "active" and
  (.bypass_actors | length) == 0 and
  ([.rules[].type] | index("merge_queue") | not) and
  any(.rules[]; .type == "required_status_checks" and .parameters.strict_required_status_checks_policy == true and .parameters.required_status_checks == [{context:"CI gate",integration_id:15368}])
' "$test_root/nix/automation/github/main-ruleset.json" >/dev/null
read -r version bump < <(printf '%s\n' 'feat!: incompatible' | "$NIXOA_CI" release version 2.0.0 auto)
[[ "$version $bump" == '3.0.0 major' ]]
read -r version bump < <(printf '%s\n' 'fix: correction' | "$NIXOA_CI" release version 2.0.0 minor)
[[ "$version $bump" == '2.1.0 minor' ]]

release_notes=$("$NIXOA_CI" release notes 1.1.0 "$test_root/CHANGELOG.md")
grep -Fq 'Security' <<<"$release_notes"
grep -Fq 'Magic Cache' <<<"$release_notes"
if grep -Fq 'Unreleased' <<<"$release_notes"; then
  printf 'Release notes include the Unreleased section.\n' >&2
  exit 1
fi
if "$NIXOA_CI" release notes 9.9.9 "$test_root/CHANGELOG.md" >/dev/null 2>&1; then
  printf 'Release notes accepted a missing version.\n' >&2
  exit 1
fi

grep -Fq 'gh release view --json tagName --jq .tagName' \
  "$test_root/nix/automation/release.sh"
if grep -Eq 'MERGE_QUEUE_TOKEN|RELEASE_AUTOMATION_LOGIN' \
  "$test_root/.github/workflows/release.yml" \
  "$test_root/.github/workflows/queue-automation.yml" \
  "$test_root/.github/workflows/update-flake-lock.yml" \
  "$test_root/docs/project-reference.md"; then
  printf 'Token-free automation still references an external merge token or owner.\n' >&2
  exit 1
fi
if grep -Fq "git tag --list 'v[0-9]*.[0-9]*.[0-9]*'" \
  "$test_root/.github/workflows/release.yml"; then
  printf 'Release automation still derives its baseline from unpublished tags.\n' >&2
  exit 1
fi

mkdir -p "$temporary/bin"
export NIXOA_CI_PATH_PREFIX="$temporary/bin"
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
  timeout 5s "$NIXOA_CI" installer boot "$temporary/installer.iso"
grep -Fq 'nixoa-installer login:' "$temporary/boot.log"

cat >"$temporary/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == 'pr view' ]]; then
  fake_head=${FAKE_HEAD_SHA:-abc123}
  if [[ -n ${FAKE_UPDATE_MARKER:-} && -e $FAKE_UPDATE_MARKER ]]; then
    if [[ -n ${FAKE_UPDATE_DELAY_MARKER:-} && ! -e $FAKE_UPDATE_DELAY_MARKER ]]; then
      touch "$FAKE_UPDATE_DELAY_MARKER"
    else
      fake_head=${FAKE_UPDATED_HEAD_SHA:-$fake_head}
    fi
  fi
  jq -n \
    --arg author "${FAKE_AUTHOR:-release-bot}" \
    --arg head "$fake_head" \
    '{author:{login:$author},baseRefName:"main",headRefName:"automation/test",headRefOid:$head,headRepository:{nameWithOwner:"example/core"},mergeStateStatus:"CLEAN",state:"OPEN",title:"Trusted update",url:"https://example.invalid/pr/1"}'
elif [[ "$1 $2" == 'run list' ]]; then
  run_head=${FAKE_RUN_HEAD_SHA:-abc123}
  run_conclusion=${FAKE_RUN_CONCLUSION:-success}
  run_status=${FAKE_RUN_STATUS:-completed}
  run_id=42
  jq -n \
    --arg conclusion "$run_conclusion" \
    --arg head "$run_head" \
    --arg status "$run_status" \
    --argjson id "$run_id" \
    '[{conclusion:$conclusion,databaseId:$id,headSha:$head,status:$status}]'
elif [[ "$1 $2" == 'run view' ]]; then
  printf '%s\n' "${FAKE_VIEW_HEAD_SHA:-abc123}"
elif [[ "$1 $2" == 'run watch' ]]; then
  exit 0
elif [[ "$1 $2" == 'pr update-branch' ]]; then
  [[ -z ${FAKE_UPDATE_MARKER:-} ]] || touch "$FAKE_UPDATE_MARKER"
elif [[ "$1 $2" == 'pr merge' ]]; then
  printf '%s\n' "$*" >"$FAKE_MERGE_LOG"
elif [[ "$1" == api && "$*" == *'/actions/runs/42/approve'* ]]; then
  [[ -z ${FAKE_APPROVAL_MARKER:-} ]] || touch "$FAKE_APPROVAL_MARKER"
elif [[ "$1" == api && "$*" == *'/pulls/1/files?'* ]]; then
  printf '%s\n' "${FAKE_FILES:-VERSION}"
elif [[ "$1" == api && "$*" == *'/contents/VERSION?'* ]]; then
  printf '%s\n' "${FAKE_VERSION:-1.2.3}"
elif [[ "$1" == api && "$*" == *'/commits/main'* ]]; then
  printf 'base123\n'
elif [[ "$1" == api && "$*" == *'/compare/base123...abc123'* ]]; then
  printf '%s\n' "${FAKE_MERGE_BASE:-base123}"
else
  printf 'unexpected gh call: %s\n' "$*" >&2
  exit 1
fi
EOF
sed -i "1c#!${BASH}" "$temporary/bin/gh"
chmod +x "$temporary/bin/gh"
trusted_env=(
  CI_POLL_INTERVAL=0
  GH_TOKEN=fixture
  GITHUB_REPOSITORY=example/core
  PR_NUMBER=1
  EXPECTED_BRANCH=automation/test
  EXPECTED_TITLE='Trusted update'
  EXPECTED_AUTHOR='release-bot'
  DEFAULT_BRANCH=main
  FAKE_MERGE_LOG="$temporary/merge.log"
)
env PATH="$temporary/bin:$PATH" "${trusted_env[@]}" \
  "$NIXOA_CI" trusted-update
grep -Fq -- '--auto' "$temporary/merge.log"
grep -Fq -- '--merge' "$temporary/merge.log"
grep -Fq -- '--match-head-commit abc123' "$temporary/merge.log"
env PATH="$temporary/bin:$PATH" FAKE_AUTHOR=app/release-bot "${trusted_env[@]}" \
  "$NIXOA_CI" trusted-update
if env PATH="$temporary/bin:$PATH" FAKE_RUN_HEAD_SHA=stale \
  "${trusted_env[@]}" "$NIXOA_CI" trusted-update >/dev/null 2>&1; then
  printf 'Trusted update accepted CI for a stale head.\n' >&2
  exit 1
fi
rm -f "$temporary/approved"
env PATH="$temporary/bin:$PATH" \
  FAKE_RUN_CONCLUSION=action_required \
  FAKE_APPROVAL_MARKER="$temporary/approved" \
  "${trusted_env[@]}" "$NIXOA_CI" trusted-update
[[ -e $temporary/approved ]]
rm -f "$temporary/updated"
rm -f "$temporary/update-delayed"
env PATH="$temporary/bin:$PATH" \
  FAKE_MERGE_BASE=older123 \
  FAKE_RUN_HEAD_SHA=def456 \
  FAKE_UPDATED_HEAD_SHA=def456 \
  FAKE_UPDATE_DELAY_MARKER="$temporary/update-delayed" \
  FAKE_UPDATE_MARKER="$temporary/updated" \
  "${trusted_env[@]}" "$NIXOA_CI" trusted-update
[[ -e $temporary/updated ]]
[[ -e $temporary/update-delayed ]]
grep -Fq -- '--match-head-commit def456' "$temporary/merge.log"
if env PATH="$temporary/bin:$PATH" FAKE_AUTHOR=attacker "${trusted_env[@]}" \
  "$NIXOA_CI" trusted-update >/dev/null 2>&1; then
  printf 'Trusted update accepted the wrong author.\n' >&2
  exit 1
fi

version_env=(
  "${trusted_env[@]}"
  EXPECTED_CHANGE_KIND=version
  EXPECTED_VERSION=1.2.3
)
env PATH="$temporary/bin:$PATH" "${version_env[@]}" \
  "$NIXOA_CI" trusted-update
if env PATH="$temporary/bin:$PATH" FAKE_VERSION=1.2.4 "${version_env[@]}" \
  "$NIXOA_CI" trusted-update >/dev/null 2>&1; then
  printf 'Trusted update accepted the wrong VERSION content.\n' >&2
  exit 1
fi
if env PATH="$temporary/bin:$PATH" FAKE_FILES=$'VERSION\nREADME.md' "${version_env[@]}" \
  "$NIXOA_CI" trusted-update >/dev/null 2>&1; then
  printf 'Trusted update accepted an extra version-PR file.\n' >&2
  exit 1
fi

lock_env=(
  "${trusted_env[@]}"
  EXPECTED_CHANGE_KIND=flake-lock
)
env PATH="$temporary/bin:$PATH" FAKE_FILES=$'devenv.lock\nflake.lock' \
  "${lock_env[@]}" "$NIXOA_CI" trusted-update
env PATH="$temporary/bin:$PATH" FAKE_FILES=flake.lock \
  "${lock_env[@]}" "$NIXOA_CI" trusted-update
if env PATH="$temporary/bin:$PATH" FAKE_FILES=$'flake.lock\nREADME.md' \
  "${lock_env[@]}" "$NIXOA_CI" trusted-update >/dev/null 2>&1; then
  printf 'Trusted lock update accepted a non-lockfile change.\n' >&2
  exit 1
fi

"$NIXOA_CI" locks validate

printf 'CI helper fixture checks passed.\n'
