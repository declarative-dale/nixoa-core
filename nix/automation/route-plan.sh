#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
state_outputs=$(mktemp "${runner_temp}/nixoa-state-outputs.XXXXXX")
plan_file=${NIXOA_CI_ROUTE_OUTPUT:-}
remove_plan=false
if [[ -z "$plan_file" ]]; then
  plan_file=$(mktemp "${runner_temp}/nixoa-route-plan.XXXXXX")
  remove_plan=true
fi
cleanup() {
  rm -f -- "$state_outputs"
  if [[ "$remove_plan" == true ]]; then
    rm -f -- "$plan_file"
  fi
}
trap cleanup EXIT

qualification_required=$(GITHUB_OUTPUT='' nixoa-ci-classify)
case "$qualification_required" in
  true | false) ;;
  *)
    printf 'Qualification classifier returned an invalid boolean: %s\n' "$qualification_required" >&2
    exit 1
    ;;
esac

mode=skip
artifact_run_id=null
media_run_id=null
media_input=null
evidence_input=null
if [[ "$qualification_required" == true ]]; then
  GITHUB_OUTPUT="$state_outputs" nixoa-ci-resolve-qualification
  mode=$(sed -n 's/^mode=//p' "$state_outputs" | tail -n 1)
  artifact_run_id=$(sed -n 's/^artifact_run_id=//p' "$state_outputs" | tail -n 1)
  media_run_id=$(sed -n 's/^media_run_id=//p' "$state_outputs" | tail -n 1)
  media_input=$(sed -n 's/^media_input=//p' "$state_outputs" | tail -n 1)
  evidence_input=$(sed -n 's/^evidence_input=//p' "$state_outputs" | tail -n 1)
  [[ "$mode" == reuse || "$mode" == refresh-evidence || "$mode" == qualify-media ]]
  [[ "$artifact_run_id" =~ ^[0-9]+$ && "$media_run_id" =~ ^[0-9]+$ ]]
  [[ "$media_input" =~ ^[0-9a-f]{64}$ && "$evidence_input" =~ ^[0-9a-f]{64}$ ]]
fi

publish_required=false
if [[ ${GITHUB_EVENT_NAME:-} == push && ${GITHUB_REF:-} == refs/heads/main && "$qualification_required" == true ]]; then
  publish_required=true
fi

if [[ "$qualification_required" == true ]]; then
  plan=$(jq -cn \
    --arg mode "$mode" \
    --arg media_input "$media_input" \
    --arg evidence_input "$evidence_input" \
    --argjson artifact_run_id "$artifact_run_id" \
    --argjson media_run_id "$media_run_id" \
    --argjson publish_required "$publish_required" \
    '{schema_version:2,qualification:{required:true,mode:$mode,artifact_run_id:$artifact_run_id,media_run_id:$media_run_id,media_input:$media_input,evidence_input:$evidence_input},publish_required:$publish_required}')
else
  plan=$(jq -cn \
    --arg mode "$mode" \
    --argjson publish_required "$publish_required" \
    '{schema_version:2,qualification:{required:false,mode:$mode,artifact_run_id:null,media_run_id:null,media_input:null,evidence_input:null},publish_required:$publish_required}')
fi

printf '%s\n' "$plan" >"$plan_file"
nixoa-ci-validate-plan "$plan_file"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'plan=%s\n' "$plan" >>"$GITHUB_OUTPUT"
else
  printf '%s\n' "$plan"
fi
