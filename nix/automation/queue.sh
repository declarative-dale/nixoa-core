#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH must be set}"

pull_requests=$(gh api --paginate \
  "repos/${GITHUB_REPOSITORY}/pulls?state=open&per_page=100" \
  --slurp)

jq -c \
  --arg branch "$DEFAULT_BRANCH" \
  --arg repository "$GITHUB_REPOSITORY" '
    add[] |
    select(.draft == false) |
    select(.head.repo.full_name == $repository) |
    select(.base.ref == $branch) |
    select(.user.login == "dependabot[bot]" or .user.login == "github-actions[bot]") |
    {rest_author:.user.login,branch:.head.ref,number,title}
  ' <<<"$pull_requests" |
while IFS= read -r pull_request; do
  export PR_NUMBER EXPECTED_BRANCH EXPECTED_TITLE EXPECTED_AUTHOR
  export EXPECTED_CHANGE_KIND=any
  unset EXPECTED_VERSION || true
  PR_NUMBER=$(jq -er .number <<<"$pull_request")
  EXPECTED_BRANCH=$(jq -er .branch <<<"$pull_request")
  EXPECTED_TITLE=$(jq -er .title <<<"$pull_request")
  rest_author=$(jq -er .rest_author <<<"$pull_request")

  if [[ "$rest_author" == 'dependabot[bot]' ]]; then
    EXPECTED_AUTHOR=dependabot
  elif [[ "$rest_author" == 'github-actions[bot]' ]]; then
    EXPECTED_AUTHOR=github-actions
    if [[ "$EXPECTED_BRANCH" == automation/weekly-flake-input-refresh &&
          "$EXPECTED_TITLE" == 'flake.lock: refresh all inputs' ]]; then
      EXPECTED_CHANGE_KIND=flake-lock
    elif [[ "$EXPECTED_BRANCH" =~ ^automation/release-v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      EXPECTED_VERSION=${BASH_REMATCH[1]}
      [[ "$EXPECTED_TITLE" == "Release NiXOA ${EXPECTED_VERSION}" ]] || continue
      EXPECTED_CHANGE_KIND=version
    elif [[ "$EXPECTED_BRANCH" =~ ^automation/start-([0-9]+\.[0-9]+\.[0-9]+-dev\.0)$ ]]; then
      EXPECTED_VERSION=${BASH_REMATCH[1]}
      [[ "$EXPECTED_TITLE" == "Start NiXOA ${EXPECTED_VERSION}" ]] || continue
      EXPECTED_CHANGE_KIND=version
    else
      continue
    fi
  else
    continue
  fi
  "$NIXOA_CI_TRUSTED_UPDATE"
done
