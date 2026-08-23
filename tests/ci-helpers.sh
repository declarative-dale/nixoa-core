#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
: "${NIXOA_CI_CLASSIFY:?NIXOA_CI_CLASSIFY must point to the packaged classifier}"
: "${NIXOA_CI_CLASSIFY_PATHS:?NIXOA_CI_CLASSIFY_PATHS must point to the packaged path classifier}"
: "${NIXOA_CI_BOOT_MEDIA:?NIXOA_CI_BOOT_MEDIA must point to the packaged media boot test}"
: "${NIXOA_CI_VERDICT:?NIXOA_CI_VERDICT must point to the packaged verdict}"
: "${NIXOA_CI_LOCK_VALIDATE:?NIXOA_CI_LOCK_VALIDATE must point to the packaged lock validator}"
: "${NIXOA_CI_ROUTE:?NIXOA_CI_ROUTE must point to the packaged work router}"
: "${NIXOA_CI_RESOLVE_QUALIFICATION:?NIXOA_CI_RESOLVE_QUALIFICATION must point to the packaged qualification resolver}"
: "${NIXOA_CI_QUALIFICATION_INPUTS:?NIXOA_CI_QUALIFICATION_INPUTS must point to the packaged input resolver}"
: "${NIXOA_CI_RELEASE_NOTES:?NIXOA_CI_RELEASE_NOTES must point to the packaged notes extractor}"
: "${NIXOA_CI_RELEASE_VERSION:?NIXOA_CI_RELEASE_VERSION must point to the packaged version selector}"
: "${NIXOA_CI_TRUSTED_UPDATE:?NIXOA_CI_TRUSTED_UPDATE must point to the packaged trusted updater}"

test_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-ci-helpers.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

[[ $(printf '%s\n' README.md docs/ci.md VERSION packer/build.sh modules/outputs/checks.nix modules/outputs/dev-shells.nix nix/checks/repository-policy.nix | "$NIXOA_CI_CLASSIFY_PATHS") == false ]]
[[ $(printf '%s\n' modules/_nixos/platform.nix | "$NIXOA_CI_CLASSIFY_PATHS") == true ]]
[[ $(printf '%s\n' nix/ci-plans.json | "$NIXOA_CI_CLASSIFY_PATHS") == true ]]
[[ $(printf '%s\n' nix/automation/qualification-assets.sh | "$NIXOA_CI_CLASSIFY_PATHS") == true ]]
[[ $(printf '%s\n' .github/workflows/ci.yml | "$NIXOA_CI_CLASSIFY_PATHS") == true ]]
[[ $(printf '%s\n' nix/automation/github/main-ruleset.json | "$NIXOA_CI_CLASSIFY_PATHS") == false ]]
[[ $(printf '%s\n' future/unknown-output | "$NIXOA_CI_CLASSIFY_PATHS") == true ]]

merge_fixture="$temporary/merge-group"
mkdir -p "$merge_fixture/docs" "$merge_fixture/modules/_nixos"
git -C "$merge_fixture" init -q
git -C "$merge_fixture" config user.email fixture@example.invalid
git -C "$merge_fixture" config user.name Fixture
printf 'fixture\n' >"$merge_fixture/README.md"
git -C "$merge_fixture" add README.md
git -C "$merge_fixture" commit -qm root
merge_base=$(git -C "$merge_fixture" rev-parse HEAD)
printf 'irrelevant\n' >"$merge_fixture/docs/irrelevant.md"
git -C "$merge_fixture" add docs/irrelevant.md
git -C "$merge_fixture" commit -qm irrelevant
irrelevant_head=$(git -C "$merge_fixture" rev-parse HEAD)
printf '{}\n' >"$merge_fixture/modules/_nixos/merge-group-fixture.nix"
git -C "$merge_fixture" add modules/_nixos/merge-group-fixture.nix
git -C "$merge_fixture" commit -qm relevant
relevant_head=$(git -C "$merge_fixture" rev-parse HEAD)
git -C "$merge_fixture" switch -q --detach "$merge_base"
mkdir -p "$merge_fixture/docs"
printf 'divergent\n' >"$merge_fixture/docs/divergent.md"
git -C "$merge_fixture" add docs/divergent.md
git -C "$merge_fixture" commit -qm divergent
divergent_head=$(git -C "$merge_fixture" rev-parse HEAD)

classifier_env=(
  EVENT_NAME=merge_group
  NIXOA_INSTALLER_POLICY="$test_root/nix/automation/installer-policy.json"
  NIXOA_SYSTEM_ROOT="$merge_fixture"
)
[[ $(env "${classifier_env[@]}" MERGE_BASE_SHA="$merge_base" MERGE_HEAD_SHA="$irrelevant_head" "$NIXOA_CI_CLASSIFY") == false ]]
[[ $(env "${classifier_env[@]}" MERGE_BASE_SHA="$merge_base" MERGE_HEAD_SHA="$relevant_head" "$NIXOA_CI_CLASSIFY") == true ]]
[[ $(env "${classifier_env[@]}" MERGE_BASE_SHA= MERGE_HEAD_SHA= "$NIXOA_CI_CLASSIFY" 2>/dev/null) == true ]]
[[ $(env "${classifier_env[@]}" MERGE_BASE_SHA="$irrelevant_head" MERGE_HEAD_SHA="$divergent_head" "$NIXOA_CI_CLASSIFY" 2>/dev/null) == true ]]

skip_plan='{"schema_version":3,"qualification":{"required":false,"mode":"skip","artifact_run_id":null,"media_run_id":null,"evidence_run_id":null,"media_input":null,"evidence_input":null},"publish_required":false}'
reuse_plan='{"schema_version":3,"qualification":{"required":true,"mode":"reuse","artifact_run_id":42,"media_run_id":41,"evidence_run_id":40,"media_input":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","evidence_input":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"publish_required":true}'
evidence_plan='{"schema_version":3,"qualification":{"required":true,"mode":"refresh-evidence","artifact_run_id":42,"media_run_id":41,"evidence_run_id":42,"media_input":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","evidence_input":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"publish_required":false}'
media_reuse_plan='{"schema_version":3,"qualification":{"required":true,"mode":"qualify-media-reuse-evidence","artifact_run_id":42,"media_run_id":42,"evidence_run_id":40,"media_input":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","evidence_input":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"publish_required":false}'
media_plan='{"schema_version":3,"qualification":{"required":true,"mode":"qualify-media","artifact_run_id":42,"media_run_id":42,"evidence_run_id":42,"media_input":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","evidence_input":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"publish_required":false}'
env ROUTE_RESULT=success CI_PLAN="$skip_plan" \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT"
env ROUTE_RESULT=success CI_PLAN="$reuse_plan" \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT"
env ROUTE_RESULT=success CI_PLAN="$evidence_plan" \
  QUALIFICATION_RESULT=success "$NIXOA_CI_VERDICT"
env ROUTE_RESULT=success CI_PLAN="$media_reuse_plan" \
  QUALIFICATION_RESULT=success "$NIXOA_CI_VERDICT"
env ROUTE_RESULT=success CI_PLAN="$media_plan" \
  QUALIFICATION_RESULT=success "$NIXOA_CI_VERDICT"
invalid_publish_plan='{"schema_version":3,"qualification":{"required":false,"mode":"skip","artifact_run_id":null,"media_run_id":null,"evidence_run_id":null,"media_input":null,"evidence_input":null},"publish_required":true}'
if env ROUTE_RESULT=success CI_PLAN="$invalid_publish_plan" \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT" >/dev/null 2>&1; then
  printf 'CI verdict accepted publication without an installer lifecycle.\n' >&2
  exit 1
fi
invalid_media_input_plan='{"schema_version":3,"qualification":{"required":true,"mode":"reuse","artifact_run_id":42,"media_run_id":41,"evidence_run_id":40,"media_input":"not-a-digest","evidence_input":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"publish_required":false}'
if env ROUTE_RESULT=success CI_PLAN="$invalid_media_input_plan" \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT" >/dev/null 2>&1; then
  printf 'CI verdict accepted an invalid media input.\n' >&2
  exit 1
fi
if env ROUTE_RESULT=failure CI_PLAN="$skip_plan" \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT"; then
  printf 'CI verdict accepted a failed repository audit.\n' >&2
  exit 1
fi
unknown_mode_plan=$(jq -c '.qualification.mode = "future-mode"' <<<"$skip_plan")
if env ROUTE_RESULT=success CI_PLAN="$unknown_mode_plan" \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT" >/dev/null 2>&1; then
  printf 'CI verdict accepted an unknown qualification mode.\n' >&2
  exit 1
fi
if env ROUTE_RESULT=success CI_PLAN='{"schema_version":3' \
  QUALIFICATION_RESULT=skipped "$NIXOA_CI_VERDICT" >/dev/null 2>&1; then
  printf 'CI verdict accepted malformed route JSON.\n' >&2
  exit 1
fi

route_output="$temporary/route-output"
env \
  EVENT_NAME=workflow_dispatch \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_OUTPUT="$route_output" \
  GITHUB_REF=refs/heads/main \
  VALIDATE_ONLY=true \
  "$NIXOA_CI_ROUTE"
routed_plan=$(sed -n 's/^plan=//p' "$route_output")
jq -e '
  .schema_version == 3 and
  (.qualification.required | not) and
  .qualification.mode == "skip" and
  (.publish_required | not)
' <<<"$routed_plan" >/dev/null

local_plan=$(
  env \
    EVENT_NAME=workflow_dispatch \
    VALIDATE_ONLY=true \
    "$NIXOA_CI_ROUTE"
)
jq -e '
  .schema_version == 3 and
  (.qualification.required | not) and
  .qualification.mode == "skip" and
  (.publish_required | not)
' <<<"$local_plan" >/dev/null
[[ ! -e nixoa-ci-route.json ]]

# The resolver distinguishes all four qualification routes and rejects
# incomplete, expired, untrusted, mismatched, or corrupt cached evidence.
qualification_bin="$temporary/qualification-bin"
qualification_artifacts="$temporary/qualification-artifacts"
qualification_work="$temporary/qualification-work"
mkdir -p "$qualification_bin" "$qualification_artifacts" "$qualification_work"
cat >"$qualification_bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${FAKE_QUALIFICATION_GRAPH:?}"
EOF
cat >"$qualification_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "run list" ]]; then
  jq -r '[77, .event] | @tsv' "${FAKE_QUALIFICATION_ARTIFACTS:?}/77/metadata.json"
  exit 0
fi
if [[ "$1 $2" == "run download" ]]; then
  run_id=$3
  artifact_name=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir) destination=$2; shift 2 ;;
      --name) artifact_name=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  source_dir="${FAKE_QUALIFICATION_ARTIFACTS:?}/$run_id/$artifact_name"
  [[ -d "$source_dir" && ! -e "$source_dir/.expired" ]]
  cp -R "$source_dir/." "$destination/"
  exit 0
fi
if [[ "$1" == api && "$2" == */artifacts ]]; then
  run_id=${2%/artifacts}
  run_id=${run_id##*/}
  if [[ "$*" == *'nixoa-evidence'* ]]; then
    artifact_name=nixoa-evidence
  else
    artifact_name=nixoa-installer
  fi
  artifact_dir="${FAKE_QUALIFICATION_ARTIFACTS:?}/$run_id/$artifact_name"
  [[ ! -d "$artifact_dir" || -e "$artifact_dir/.expired" ]] || printf '900\n'
  exit 0
fi
if [[ "$1" == api && "$2" == */actions/runs/* ]]; then
  run_id=${2##*/}
  if [[ "$*" == *'head_repository.full_name // empty'* ]]; then
    jq -r '.head_repository // empty' "${FAKE_QUALIFICATION_ARTIFACTS:?}/$run_id/metadata.json"
  else
    jq -r '[.event, (.head_repository // "")] | @tsv' \
      "${FAKE_QUALIFICATION_ARTIFACTS:?}/$run_id/metadata.json"
  fi
  exit 0
fi
exit 1
EOF
sed -i "1c#!${BASH}" "$qualification_bin/nix" "$qualification_bin/gh"
chmod +x "$qualification_bin/nix" "$qualification_bin/gh"

baseline_graph='{"media":{"installer":"/nix/store/media-a"},"evidence":{"system":"/nix/store/system-a"}}'
baseline_inputs=$(NIXOA_CI_PATH_PREFIX="$qualification_bin" \
  NIXOA_SYSTEM_ROOT="$qualification_work" \
  FAKE_QUALIFICATION_GRAPH="$baseline_graph" \
  "$NIXOA_CI_QUALIFICATION_INPUTS")
baseline_media=$(jq -er .media_input <<<"$baseline_inputs")
baseline_evidence=$(jq -er .evidence_input <<<"$baseline_inputs")

reset_qualification_artifacts() {
  rm -rf -- "$qualification_artifacts/77"
  mkdir -p \
    "$qualification_artifacts/77/nixoa-qualification-state" \
    "$qualification_artifacts/77/nixoa-installer" \
    "$qualification_artifacts/77/nixoa-evidence"
  printf '%s\n' '{"event":"push","head_repository":"example/nixoa"}' \
    >"$qualification_artifacts/77/metadata.json"
  jq -n --arg media_input "$baseline_media" --arg evidence_input "$baseline_evidence" '
    {
      schema_version:4,
      mode:"qualify-media",
      media_input:$media_input,
      evidence_input:$evidence_input,
      source_commit:"old-source",
      artifact_source_commit:"old-source",
      media_source_commit:"old-source",
      producer_event:"push",
      artifact_run_id:77,
      media_run_id:77,
      evidence_run_id:77
    }
  ' >"$qualification_artifacts/77/nixoa-qualification-state/nixoa-qualification-state.json"
  cp "$qualification_artifacts/77/nixoa-qualification-state/nixoa-qualification-state.json" \
    "$qualification_artifacts/77/nixoa-evidence/nixoa-qualification-state.json"
  printf '%s\n' '{"spdxVersion":"SPDX-2.3"}' \
    >"$qualification_artifacts/77/nixoa-evidence/nixoa-system.spdx.json"
  printf '%s\n' '{"bomFormat":"CycloneDX"}' \
    >"$qualification_artifacts/77/nixoa-evidence/nixoa-system.cdx.json"
  printf '%s\n' '{"schemaVersion":1}' \
    >"$qualification_artifacts/77/nixoa-evidence/xen-orchestra-supply.assertion.json"
  printf '%s\n' '{"spdxVersion":"SPDX-2.3"}' \
    >"$qualification_artifacts/77/nixoa-evidence/xen-orchestra-supply.spdx.json"
  printf '%s\n' '{"bomFormat":"CycloneDX"}' \
    >"$qualification_artifacts/77/nixoa-evidence/xen-orchestra-supply.cdx.json"
  (
    cd "$qualification_artifacts/77/nixoa-evidence"
    sha256sum nixoa-system.spdx.json >nixoa-system.spdx.json.sha256
    sha256sum nixoa-system.cdx.json >nixoa-system.cdx.json.sha256
    sha256sum xen-orchestra-supply.assertion.json >xen-orchestra-supply.assertion.json.sha256
    sha256sum xen-orchestra-supply.spdx.json >xen-orchestra-supply.spdx.json.sha256
    sha256sum xen-orchestra-supply.cdx.json >xen-orchestra-supply.cdx.json.sha256
  )
}

resolve_mode() {
  local graph=$1
  local output=$qualification_work/output
  rm -f "$output" "$qualification_work/nixoa-qualification-state.json"
  (
    cd "$qualification_work"
    NIXOA_CI_PATH_PREFIX="$qualification_bin" \
      NIXOA_SYSTEM_ROOT="$qualification_work" \
      FAKE_QUALIFICATION_GRAPH="$graph" \
      FAKE_QUALIFICATION_ARTIFACTS="$qualification_artifacts" \
      GITHUB_OUTPUT="$output" \
      GITHUB_REPOSITORY=example/nixoa \
      GITHUB_RUN_ID=99 \
      GITHUB_SHA=current-source \
      "$NIXOA_CI_RESOLVE_QUALIFICATION" >/dev/null
  )
  sed -n 's/^mode=//p' "$output"
}

reset_qualification_artifacts
[[ $(resolve_mode "$baseline_graph") == reuse ]]
reset_qualification_artifacts
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-a"},"evidence":{"system":"/nix/store/system-b"}}') == refresh-evidence ]]
reset_qualification_artifacts
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-b"},"evidence":{"system":"/nix/store/system-a"}}') == qualify-media-reuse-evidence ]]
reset_qualification_artifacts
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-b"},"evidence":{"system":"/nix/store/system-b"}}') == qualify-media ]]

reset_qualification_artifacts
rm -rf -- "$qualification_artifacts/77/nixoa-evidence"
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-b"},"evidence":{"system":"/nix/store/system-a"}}') == qualify-media ]]

reset_qualification_artifacts
touch "$qualification_artifacts/77/nixoa-evidence/.expired"
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-b"},"evidence":{"system":"/nix/store/system-a"}}') == qualify-media ]]

reset_qualification_artifacts
printf '%s\n' '{"event":"pull_request","head_repository":"attacker/fork"}' \
  >"$qualification_artifacts/77/metadata.json"
[[ $(resolve_mode "$baseline_graph") == qualify-media ]]

reset_qualification_artifacts
jq '.evidence_input = "state-mismatch"' \
  "$qualification_artifacts/77/nixoa-evidence/nixoa-qualification-state.json" \
  >"$qualification_work/mismatched-state.json"
mv "$qualification_work/mismatched-state.json" \
  "$qualification_artifacts/77/nixoa-evidence/nixoa-qualification-state.json"
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-b"},"evidence":{"system":"/nix/store/system-a"}}') == qualify-media ]]

reset_qualification_artifacts
printf 'corrupt\n' >>"$qualification_artifacts/77/nixoa-evidence/nixoa-system.spdx.json"
[[ $(resolve_mode '{"media":{"installer":"/nix/store/media-b"},"evidence":{"system":"/nix/store/system-a"}}') == qualify-media ]]

read -r version bump < <(printf '%s\n' 'fix: correction' | "$NIXOA_CI_RELEASE_VERSION" 2.0.0 auto)
[[ "$version $bump" == '2.0.1 patch' ]]
read -r version bump < <(printf '%s\n' 'fix: correction' | "$NIXOA_CI_RELEASE_VERSION" 1.0 auto)
[[ "$version $bump" == '1.0.1 patch' ]]
read -r version bump < <(printf '%s\n' 'feat(core): capability' | "$NIXOA_CI_RELEASE_VERSION" 2.0.0 auto)
[[ "$version $bump" == '2.1.0 minor' ]]

jq -e '
  .enforcement == "active" and
  (.bypass_actors | length) == 0 and
  any(.rules[]; .type == "merge_queue" and
    .parameters.merge_method == "MERGE" and
    .parameters.max_entries_to_merge == 1) and
  any(.rules[]; .type == "required_status_checks" and .parameters.strict_required_status_checks_policy == false and .parameters.required_status_checks == [{context:"Required CI verdict",integration_id:15368}])
' "$test_root/nix/automation/github/main-ruleset.json" >/dev/null
read -r version bump < <(printf '%s\n' 'feat!: incompatible' | "$NIXOA_CI_RELEASE_VERSION" 2.0.0 auto)
[[ "$version $bump" == '3.0.0 major' ]]
read -r version bump < <(printf '%s\n' 'fix: correction' | "$NIXOA_CI_RELEASE_VERSION" 2.0.0 minor)
[[ "$version $bump" == '2.1.0 minor' ]]

release_notes=$("$NIXOA_CI_RELEASE_NOTES" 1.1.0 "$test_root/CHANGELOG.md")
grep -Fq 'Security' <<<"$release_notes"
grep -Fq 'Magic Cache' <<<"$release_notes"
if grep -Fq 'Unreleased' <<<"$release_notes"; then
  printf 'Release notes include the Unreleased section.\n' >&2
  exit 1
fi
if "$NIXOA_CI_RELEASE_NOTES" 9.9.9 "$test_root/CHANGELOG.md" >/dev/null 2>&1; then
  printf 'Release notes accepted a missing version.\n' >&2
  exit 1
fi

grep -Fq 'gh release view --json tagName --jq .tagName' \
  "$test_root/nix/automation/release-manager.sh"
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
  timeout 5s "$NIXOA_CI_BOOT_MEDIA" "$temporary/installer.iso"
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
  if [[ -n ${FAKE_DISPATCH_MARKER:-} && ! -e $FAKE_DISPATCH_MARKER ]]; then
    printf '[]\n'
    exit 0
  fi
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
elif [[ "$1 $2" == 'pr update-branch' ]]; then
  [[ -z ${FAKE_UPDATE_MARKER:-} ]] || touch "$FAKE_UPDATE_MARKER"
elif [[ "$1 $2" == 'pr merge' ]]; then
  printf '%s\n' "$*" >"$FAKE_MERGE_LOG"
elif [[ "$1 $2" == 'workflow run' ]]; then
  [[ -z ${FAKE_DISPATCH_MARKER:-} ]] || touch "$FAKE_DISPATCH_MARKER"
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
  "$NIXOA_CI_TRUSTED_UPDATE"
grep -Fq -- '--auto' "$temporary/merge.log"
grep -Fq -- '--merge' "$temporary/merge.log"
grep -Fq -- '--match-head-commit abc123' "$temporary/merge.log"
env PATH="$temporary/bin:$PATH" FAKE_AUTHOR=app/release-bot "${trusted_env[@]}" \
  "$NIXOA_CI_TRUSTED_UPDATE"
if env PATH="$temporary/bin:$PATH" FAKE_RUN_HEAD_SHA=stale \
  "${trusted_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE" >/dev/null 2>&1; then
  printf 'Trusted update accepted CI for a stale head.\n' >&2
  exit 1
fi
rm -f "$temporary/approved"
env PATH="$temporary/bin:$PATH" \
  FAKE_RUN_CONCLUSION=action_required \
  FAKE_APPROVAL_MARKER="$temporary/approved" \
  "${trusted_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE"
[[ -e $temporary/approved ]]
rm -f "$temporary/dispatched"
env PATH="$temporary/bin:$PATH" \
  FAKE_DISPATCH_MARKER="$temporary/dispatched" \
  "${trusted_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE"
[[ -e $temporary/dispatched ]]
rm -f "$temporary/updated"
rm -f "$temporary/update-delayed"
env PATH="$temporary/bin:$PATH" \
  FAKE_MERGE_BASE=older123 \
  FAKE_RUN_HEAD_SHA=def456 \
  FAKE_UPDATED_HEAD_SHA=def456 \
  FAKE_UPDATE_DELAY_MARKER="$temporary/update-delayed" \
  FAKE_UPDATE_MARKER="$temporary/updated" \
  "${trusted_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE"
[[ -e $temporary/updated ]]
[[ -e $temporary/update-delayed ]]
grep -Fq -- '--match-head-commit def456' "$temporary/merge.log"
if env PATH="$temporary/bin:$PATH" FAKE_AUTHOR=attacker "${trusted_env[@]}" \
  "$NIXOA_CI_TRUSTED_UPDATE" >/dev/null 2>&1; then
  printf 'Trusted update accepted the wrong author.\n' >&2
  exit 1
fi

version_env=(
  "${trusted_env[@]}"
  EXPECTED_CHANGE_KIND=version
  EXPECTED_VERSION=1.2.3
)
env PATH="$temporary/bin:$PATH" "${version_env[@]}" \
  "$NIXOA_CI_TRUSTED_UPDATE"
if env PATH="$temporary/bin:$PATH" FAKE_VERSION=1.2.4 "${version_env[@]}" \
  "$NIXOA_CI_TRUSTED_UPDATE" >/dev/null 2>&1; then
  printf 'Trusted update accepted the wrong VERSION content.\n' >&2
  exit 1
fi
if env PATH="$temporary/bin:$PATH" FAKE_FILES=$'VERSION\nREADME.md' "${version_env[@]}" \
  "$NIXOA_CI_TRUSTED_UPDATE" >/dev/null 2>&1; then
  printf 'Trusted update accepted an extra version-PR file.\n' >&2
  exit 1
fi

lock_env=(
  "${trusted_env[@]}"
  EXPECTED_CHANGE_KIND=flake-lock
)
env PATH="$temporary/bin:$PATH" FAKE_FILES=$'devenv.lock\nflake.lock' \
  "${lock_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE"
env PATH="$temporary/bin:$PATH" FAKE_FILES=flake.lock \
  "${lock_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE"
if env PATH="$temporary/bin:$PATH" FAKE_FILES=$'flake.lock\nREADME.md' \
  "${lock_env[@]}" "$NIXOA_CI_TRUSTED_UPDATE" >/dev/null 2>&1; then
  printf 'Trusted lock update accepted a non-lockfile change.\n' >&2
  exit 1
fi

"$NIXOA_CI_LOCK_VALIDATE"

printf 'CI helper fixture checks passed.\n'
