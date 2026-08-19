#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

event_name=${EVENT_NAME:-${GITHUB_EVENT_NAME:-}}
installer=true
base_sha=
head_sha=

case "$event_name" in
  pull_request)
    base_sha=${PR_BASE_SHA:-}
    head_sha=${PR_HEAD_SHA:-}
    ;;
  push)
    base_sha=${PUSH_BASE_SHA:-}
    head_sha=${PUSH_HEAD_SHA:-${GITHUB_SHA:-}}
    if [[ "$base_sha" == 0000000000000000000000000000000000000000 ]]; then
      base_sha=
    fi
    ;;
  schedule)
    ;;
  workflow_dispatch)
    if [[ ${VALIDATE_ONLY:-false} == true ]]; then
      installer=false
    fi
    ;;
  *)
    printf 'Unknown event %s; requiring installer validation.\n' "$event_name" >&2
    ;;
esac

if [[ -n "$base_sha" && -n "$head_sha" ]]; then
  changed_paths=$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nixoa-changes.XXXXXX")
  trap 'rm -f -- "$changed_paths"' EXIT
  if git -C "$NIXOA_SYSTEM_ROOT" diff --name-only "$base_sha" "$head_sha" >"$changed_paths"; then
    installer=$(nixoa-ci-classify-paths <"$changed_paths")
  else
    printf 'Could not determine changed paths; requiring installer validation.\n' >&2
    installer=true
  fi
fi

if [[ ${FORCE_ARTIFACT:-false} == true ]]; then
  installer=true
fi

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'installer=%s\n' "$installer" >>"$GITHUB_OUTPUT"
else
  printf '%s\n' "$installer"
fi
