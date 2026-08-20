#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test "${PREPARE_RESULT:?}" = success
: "${CI_PLAN:?CI_PLAN must contain the prepare job JSON output}"
runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
plan_file=$(mktemp "${runner_temp}/nixoa-ci-plan.XXXXXX")
trap 'rm -f -- "$plan_file"' EXIT
printf '%s\n' "$CI_PLAN" >"$plan_file"
nixoa-ci-validate-plan "$plan_file"

if [[ $(jq -r '.installer.build_required' <<<"$CI_PLAN") == true ]]; then
  test "${BUILD_RESULT:?}" = success
else
  test "${BUILD_RESULT:?}" = skipped
fi
