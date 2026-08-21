#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test "${ROUTE_RESULT:?}" = success
: "${CI_PLAN:?CI_PLAN must contain the route decision JSON output}"
runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
plan_file=$(mktemp "${runner_temp}/nixoa-route-plan.XXXXXX")
trap 'rm -f -- "$plan_file"' EXIT
printf '%s\n' "$CI_PLAN" >"$plan_file"
nixoa-ci-validate-plan "$plan_file"

mode=$(jq -r '.qualification.mode' <<<"$CI_PLAN")
case "$mode" in
  refresh-evidence|qualify-media-reuse-evidence|qualify-media)
    test "${QUALIFICATION_RESULT:?}" = success
    ;;
  skip|reuse)
    test "${QUALIFICATION_RESULT:?}" = skipped
    ;;
esac
