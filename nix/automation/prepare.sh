#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
state_outputs=$(mktemp "${runner_temp}/nixoa-state-outputs.XXXXXX")
trap 'rm -f -- "$state_outputs"' EXIT

installer_required=$(GITHUB_OUTPUT='' nixoa-ci-classify)
case "$installer_required" in
  true | false) ;;
  *)
    printf 'Installer classifier returned an invalid boolean: %s\n' "$installer_required" >&2
    exit 1
    ;;
esac

build_required=false
artifact_run_id=null
build_input=null
if [[ "$installer_required" == true ]]; then
  GITHUB_OUTPUT="$state_outputs" nixoa-ci-resolve-state
  build_required=$(sed -n 's/^should_build=//p' "$state_outputs" | tail -n 1)
  artifact_run_id=$(sed -n 's/^artifact_run_id=//p' "$state_outputs" | tail -n 1)
  build_input=$(sed -n 's/^build_input=//p' "$state_outputs" | tail -n 1)
  [[ "$build_required" == true || "$build_required" == false ]]
  [[ "$artifact_run_id" =~ ^[0-9]+$ ]]
  [[ "$build_input" =~ ^[0-9a-f]{64}$ ]]
fi

publish_required=false
if [[ ${GITHUB_EVENT_NAME:-} == push && ${GITHUB_REF:-} == refs/heads/main && "$installer_required" == true ]]; then
  publish_required=true
fi

if [[ "$installer_required" == true ]]; then
  plan=$(jq -cn \
    --argjson artifact_run_id "$artifact_run_id" \
    --arg build_input "$build_input" \
    --argjson build_required "$build_required" \
    --argjson installer_required "$installer_required" \
    --argjson publish_required "$publish_required" \
    '{schema_version:1,installer:{required:$installer_required,build_required:$build_required,artifact_run_id:$artifact_run_id,build_input:$build_input},publish_required:$publish_required}')
else
  plan=$(jq -cn \
    --argjson build_required "$build_required" \
    --argjson installer_required "$installer_required" \
    --argjson publish_required "$publish_required" \
    '{schema_version:1,installer:{required:$installer_required,build_required:$build_required,artifact_run_id:null,build_input:null},publish_required:$publish_required}')
fi

printf '%s\n' "$plan" >"${NIXOA_CI_PLAN_FILE:-nixoa-ci-plan.json}"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'plan=%s\n' "$plan" >>"$GITHUB_OUTPUT"
else
  printf '%s\n' "$plan"
fi
