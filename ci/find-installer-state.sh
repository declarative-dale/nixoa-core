#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
: "${GITHUB_SHA:?GITHUB_SHA must be set}"

workflow=${CI_WORKFLOW:-ci.yml}
allow_reuse=${ALLOW_REUSE:-true}
force_build=${FORCE_BUILD:-false}
runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
build_input=$(./ci/installer-build-input.sh)
artifact_run_id=$GITHUB_RUN_ID
artifact_source_commit=$GITHUB_SHA
producer_event=${GITHUB_EVENT_NAME:-workflow_dispatch}
should_build=true

if [[ "$allow_reuse" == true && "$force_build" != true ]]; then
  while IFS=$'\t' read -r run_id run_event; do
    [[ "$run_id" =~ ^[0-9]+$ ]] || continue
    case "$run_event" in
      pull_request)
        head_repository=$(gh api \
          "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}" \
          --jq '.head_repository.full_name // empty')
        [[ "$head_repository" == "$GITHUB_REPOSITORY" ]] || continue
        ;;
      push|schedule|workflow_dispatch) ;;
      *) continue ;;
    esac
    state_dir=$(mktemp -d "${runner_temp}/nixoa-state.XXXXXX")
    if gh run download "$run_id" \
      --repo "$GITHUB_REPOSITORY" \
      --name nixoa-build-state \
      --dir "$state_dir" >/dev/null 2>&1 &&
      jq -e \
        --arg build_input "$build_input" \
        '.schema_version == 2 and .build_input == $build_input and (.artifact_run_id | type == "number")' \
        "$state_dir/nixoa-build-state.json" >/dev/null; then
      candidate_run_id=$(jq -r .artifact_run_id "$state_dir/nixoa-build-state.json")
      candidate_source_commit=$(jq -r .artifact_source_commit "$state_dir/nixoa-build-state.json")
      candidate_event=$(jq -r .producer_event "$state_dir/nixoa-build-state.json")
      available=$(gh api \
        "repos/${GITHUB_REPOSITORY}/actions/runs/${candidate_run_id}/artifacts" \
        --jq '.artifacts[] | select(.name == "nixoa-installer" and (.expired | not)) | .id' |
        head -n 1)
      if [[ -n "$available" ]]; then
        artifact_run_id=$candidate_run_id
        artifact_source_commit=$candidate_source_commit
        producer_event=$candidate_event
        should_build=false
        rm -rf -- "$state_dir"
        break
      fi
    fi
    rm -rf -- "$state_dir"
  done < <(
    gh run list \
      --repo "$GITHUB_REPOSITORY" \
      --workflow "$workflow" \
      --status completed \
      --limit 100 \
      --json databaseId,event \
      --jq '.[] | [.databaseId, .event] | @tsv'
  )
fi

jq -n \
  --arg build_input "$build_input" \
  --arg source_commit "$GITHUB_SHA" \
  --arg artifact_source_commit "$artifact_source_commit" \
  --arg producer_event "$producer_event" \
  --argjson artifact_run_id "$artifact_run_id" \
  '{schema_version:2,build_input:$build_input,source_commit:$source_commit,artifact_source_commit:$artifact_source_commit,producer_event:$producer_event,artifact_run_id:$artifact_run_id}' \
  >nixoa-build-state.json

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    printf 'artifact_run_id=%s\n' "$artifact_run_id"
    printf 'build_input=%s\n' "$build_input"
    printf 'should_build=%s\n' "$should_build"
  } >>"$GITHUB_OUTPUT"
fi
if [[ "$should_build" == true ]]; then
  state_description=requires-build
else
  state_description=reused
fi
printf 'Installer state %s; artifact run %s.\n' "$state_description" "$artifact_run_id"
