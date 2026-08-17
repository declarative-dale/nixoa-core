#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${EXPECTED_BRANCH:?EXPECTED_BRANCH must be set}"
: "${EXPECTED_TITLE:?EXPECTED_TITLE must be set}"
: "${EXPECTED_AUTHOR:?EXPECTED_AUTHOR must be set}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH must be set}"

ci_workflow=${CI_WORKFLOW:-ci.yml}
wait_for_merge=${WAIT_FOR_MERGE:-false}
validate_only=${VALIDATE_ONLY:-false}
expected_change_kind=${EXPECTED_CHANGE_KIND:-any}

read_pr() {
  gh pr view "$PR_NUMBER" \
    --repo "$GITHUB_REPOSITORY" \
    --json author,baseRefName,headRefName,headRefOid,headRepository,mergeStateStatus,state,title,url
}

validate_pr() {
  local candidate=$1
  [[ $(jq -er .state <<<"$candidate") == OPEN ]]
  [[ $(jq -er .title <<<"$candidate") == "$EXPECTED_TITLE" ]]
  [[ $(jq -er .author.login <<<"$candidate") == "$EXPECTED_AUTHOR" ]]
  [[ $(jq -er .baseRefName <<<"$candidate") == "$DEFAULT_BRANCH" ]]
  [[ $(jq -er .headRepository.nameWithOwner <<<"$candidate") == "$GITHUB_REPOSITORY" ]]
  [[ $(jq -er .headRefName <<<"$candidate") == "$EXPECTED_BRANCH" ]]
}

validate_changes() {
  local candidate=$1
  local head_sha
  local -a changed_files

  case "$expected_change_kind" in
    any)
      return
      ;;
    flake-lock | version)
      mapfile -t changed_files < <(
        gh api --paginate \
          "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files?per_page=100" \
          --jq '.[].filename'
      )
      ;;
    *)
      printf 'Unknown trusted change kind: %s\n' "$expected_change_kind" >&2
      return 1
      ;;
  esac

  [[ ${#changed_files[@]} -eq 1 ]]
  if [[ "$expected_change_kind" == flake-lock ]]; then
    [[ ${changed_files[0]} == flake.lock ]]
    return
  fi

  : "${EXPECTED_VERSION:?EXPECTED_VERSION must be set for version changes}"
  [[ ${changed_files[0]} == VERSION ]]
  head_sha=$(jq -er .headRefOid <<<"$candidate")
  [[ $(gh api \
    -H 'Accept: application/vnd.github.raw+json' \
    "repos/${GITHUB_REPOSITORY}/contents/VERSION?ref=${head_sha}") == "$EXPECTED_VERSION" ]]
}

pr=$(read_pr)
validate_pr "$pr"
validate_changes "$pr"
if [[ $(jq -er .mergeStateStatus <<<"$pr") == BEHIND ]]; then
  gh pr update-branch "$PR_NUMBER" --repo "$GITHUB_REPOSITORY"
  pr=$(read_pr)
  validate_pr "$pr"
  validate_changes "$pr"
fi
branch=$(jq -er .headRefName <<<"$pr")
head_sha=$(jq -er .headRefOid <<<"$pr")
pr_url=$(jq -er .url <<<"$pr")

run_id=
for _ in {1..6}; do
  run_id=$(gh run list \
    --repo "$GITHUB_REPOSITORY" \
    --workflow "$ci_workflow" \
    --event pull_request \
    --branch "$branch" \
    --commit "$head_sha" \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty')
  [[ -z "$run_id" ]] || break
  sleep 5
done

if [[ -z "$run_id" ]]; then
  previous_run_id=$(gh run list \
    --repo "$GITHUB_REPOSITORY" \
    --workflow "$ci_workflow" \
    --event workflow_dispatch \
    --branch "$branch" \
    --commit "$head_sha" \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty')
  gh workflow run "$ci_workflow" \
    --repo "$GITHUB_REPOSITORY" \
    --ref "$branch" \
    -f "validate_only=${validate_only}"
  for _ in {1..24}; do
    run_id=$(gh run list \
      --repo "$GITHUB_REPOSITORY" \
      --workflow "$ci_workflow" \
      --event workflow_dispatch \
      --branch "$branch" \
      --commit "$head_sha" \
      --limit 5 \
      --json databaseId \
      --jq ".[] | select((.databaseId | tostring) != \"${previous_run_id}\") | .databaseId" |
      head -n 1)
    [[ -z "$run_id" ]] || break
    sleep 5
  done
fi

[[ -n "$run_id" ]] || {
  printf 'Could not locate CI for trusted update %s.\n' "$PR_NUMBER" >&2
  exit 1
}
gh run watch "$run_id" --repo "$GITHUB_REPOSITORY" --exit-status
gh pr merge \
  --repo "$GITHUB_REPOSITORY" \
  --auto \
  --merge \
  --match-head-commit "$head_sha" \
  "$pr_url"

if [[ "$wait_for_merge" == true ]]; then
  for _ in {1..240}; do
    state=$(gh pr view "$PR_NUMBER" \
      --repo "$GITHUB_REPOSITORY" \
      --json mergeCommit,state)
    if [[ $(jq -r .state <<<"$state") == MERGED ]]; then
      jq -er .mergeCommit.oid <<<"$state"
      exit 0
    fi
    sleep 30
  done
  printf 'Timed out waiting for trusted update %s to merge.\n' "$PR_NUMBER" >&2
  exit 1
fi
