#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

test "${ROUTE_RESULT:?}" = success
: "${CI_PLAN:?CI_PLAN must contain the route decision JSON output}"

# Keep the required verdict runnable on GitHub's slim image. This is the
# schema-v3 contract enforced by qualification-plan.schema.json, expressed in
# runner-provided jq so this final gate does not bootstrap Nix and devenv.
jq -e '
  type == "object" and
  (keys | sort) == ["publish_required", "qualification", "schema_version"] and
  .schema_version == 3 and
  (.publish_required | type == "boolean") and
  (.qualification | type == "object") and
  (.qualification | keys | sort) == [
    "artifact_run_id", "evidence_input", "evidence_run_id", "media_input",
    "media_run_id", "mode", "required"
  ] and
  (.qualification.required | type == "boolean") and
  (.qualification.mode | IN(
    "skip", "reuse", "refresh-evidence",
    "qualify-media-reuse-evidence", "qualify-media"
  )) and
  (if .qualification.required then
    .qualification.mode != "skip" and
    all([
      .qualification.artifact_run_id,
      .qualification.media_run_id,
      .qualification.evidence_run_id
    ][]; type == "number" and floor == . and . >= 1) and
    all([.qualification.media_input, .qualification.evidence_input][];
      type == "string" and test("^[0-9a-f]{64}$"))
  else
    .qualification.mode == "skip" and
    all([
      .qualification.artifact_run_id,
      .qualification.media_run_id,
      .qualification.evidence_run_id,
      .qualification.media_input,
      .qualification.evidence_input
    ][]; . == null)
  end) and
  ((.publish_required | not) or .qualification.required)
' <<<"$CI_PLAN" >/dev/null

mode=$(jq -er '.qualification.mode' <<<"$CI_PLAN")
case "$mode" in
  refresh-evidence|qualify-media-reuse-evidence|qualify-media)
    test "${QUALIFICATION_RESULT:?}" = success
    ;;
  skip|reuse)
    test "${QUALIFICATION_RESULT:?}" = skipped
    ;;
  *)
    printf 'Unknown qualification mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
