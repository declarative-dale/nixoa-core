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
inputs=$(nixoa-ci-qualification-inputs)
media_input=$(jq -er .media_input <<<"$inputs")
evidence_input=$(jq -er .evidence_input <<<"$inputs")

mode=qualify-media
artifact_run_id=$GITHUB_RUN_ID
media_run_id=$GITHUB_RUN_ID
artifact_source_commit=$GITHUB_SHA
media_source_commit=$GITHUB_SHA
producer_event=${GITHUB_EVENT_NAME:-workflow_dispatch}

fallback_run_id=
fallback_source_commit=

artifact_available() {
  local run_id=$1
  gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/artifacts" \
    --jq '.artifacts[] | select(.name == "nixoa-installer" and (.expired | not)) | .id' |
    head -n 1
}

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
      --name nixoa-qualification-state \
      --dir "$state_dir" >/dev/null 2>&1 &&
      jq -e '
        .schema_version == 3 and
        (.artifact_run_id | type == "number") and
        (.media_run_id | type == "number") and
        (.media_input | type == "string") and
        (.evidence_input | type == "string") and
        (.artifact_source_commit | type == "string") and
        (.media_source_commit | type == "string")
      ' \
        "$state_dir/nixoa-qualification-state.json" >/dev/null; then
      candidate_media=$(jq -r .media_input "$state_dir/nixoa-qualification-state.json")
      if [[ "$candidate_media" == "$media_input" ]]; then
        candidate_run_id=$(jq -r .artifact_run_id "$state_dir/nixoa-qualification-state.json")
        available=$(artifact_available "$candidate_run_id")
        if [[ -n "$available" ]]; then
          candidate_source_commit=$(jq -r .artifact_source_commit "$state_dir/nixoa-qualification-state.json")
          candidate_event=$(jq -r .producer_event "$state_dir/nixoa-qualification-state.json")
          candidate_media_source=$(jq -r .media_source_commit "$state_dir/nixoa-qualification-state.json")
          if [[ $(jq -r .evidence_input "$state_dir/nixoa-qualification-state.json") == "$evidence_input" ]]; then
            mode=reuse
            artifact_run_id=$candidate_run_id
            media_run_id=$(jq -r .media_run_id "$state_dir/nixoa-qualification-state.json")
            artifact_source_commit=$candidate_source_commit
            media_source_commit=$candidate_media_source
            producer_event=$candidate_event
            rm -rf -- "$state_dir"
            break
          fi
          if [[ -z "$fallback_run_id" ]]; then
            fallback_run_id=$candidate_run_id
            fallback_source_commit=$candidate_media_source
          fi
        fi
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

if [[ "$mode" == qualify-media && -n "$fallback_run_id" ]]; then
  mode=refresh-evidence
  media_run_id=$fallback_run_id
  media_source_commit=$fallback_source_commit
fi

jq -n \
  --arg mode "$mode" \
  --arg media_input "$media_input" \
  --arg evidence_input "$evidence_input" \
  --arg source_commit "$GITHUB_SHA" \
  --arg artifact_source_commit "$artifact_source_commit" \
  --arg media_source_commit "$media_source_commit" \
  --arg producer_event "$producer_event" \
  --argjson artifact_run_id "$artifact_run_id" \
  --argjson media_run_id "$media_run_id" \
  '{schema_version:3,mode:$mode,media_input:$media_input,evidence_input:$evidence_input,source_commit:$source_commit,artifact_source_commit:$artifact_source_commit,media_source_commit:$media_source_commit,producer_event:$producer_event,artifact_run_id:$artifact_run_id,media_run_id:$media_run_id}' \
  >nixoa-qualification-state.json

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    printf 'mode=%s\n' "$mode"
    printf 'artifact_run_id=%s\n' "$artifact_run_id"
    printf 'media_run_id=%s\n' "$media_run_id"
    printf 'media_input=%s\n' "$media_input"
    printf 'evidence_input=%s\n' "$evidence_input"
  } >>"$GITHUB_OUTPUT"
fi
printf 'Qualification mode %s; artifact run %s; media run %s.\n' \
  "$mode" "$artifact_run_id" "$media_run_id"
