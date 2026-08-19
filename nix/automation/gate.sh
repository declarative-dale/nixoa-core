#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test "${PREPARE_RESULT:?}" = success
: "${CI_PLAN:?CI_PLAN must contain the prepare job JSON output}"
jq -e '
  .schema_version == 1 and
  (.installer.required | type == "boolean") and
  (.installer.build_required | type == "boolean") and
  (.publish_required | type == "boolean") and
  (if .installer.required then
    (.installer.artifact_run_id | type == "number") and
    (.installer.build_input | type == "string")
  else
    .installer.artifact_run_id == null and
    .installer.build_input == null and
    (.installer.build_required | not)
  end)
' <<<"$CI_PLAN" >/dev/null

if [[ $(jq -r '.installer.build_required' <<<"$CI_PLAN") == true ]]; then
  test "${BUILD_RESULT:?}" = success
else
  test "${BUILD_RESULT:?}" = skipped
fi
