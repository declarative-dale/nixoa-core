#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

prepare() {
  : "${GITHUB_REF:?}" "${GITHUB_SHA:?}" "${GITHUB_REPOSITORY:?}"
  : "${DEFAULT_BRANCH:?}" "${EXPECTED_AUTHOR:?}" "${REQUESTED_BUMP:?}"
  [[ "$GITHUB_REF" == refs/heads/main ]]
  initial_sha=$(git rev-parse HEAD)
  [[ "$initial_sha" == "$GITHUB_SHA" ]] || {
    printf 'Main advanced after this release was dispatched.\n' >&2
    return 1
  }
  source_version=$(<VERSION)
  [[ "$source_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+)?$ ]]

  last_tag=$(gh release view --json tagName --jq .tagName 2>/dev/null || true)
  if [[ -n "$last_tag" ]]; then
    [[ "$last_tag" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
    git rev-parse --verify "refs/tags/${last_tag}" >/dev/null
  fi

  if [[ -z "$last_tag" ]]; then
    version=${source_version%%-dev.*}
    selected_bump=initial
  else
    git merge-base --is-ancestor "$last_tag" HEAD
    meaningful_commits=$(git log "${last_tag}..HEAD" \
      --format='%H' \
      --invert-grep \
      --grep='^Release NiXOA [0-9]\+\.[0-9]\+\.[0-9]\+$' \
      --grep='^Start NiXOA [0-9]\+\.[0-9]\+\.[0-9]\+-dev\.[0-9]\+$')
    [[ -n "$meaningful_commits" ]] || {
      printf 'No releasable commits exist after %s.\n' "$last_tag" >&2
      return 1
    }
    release_log=$(git log "${last_tag}..HEAD" \
      --format='%s%n%b' \
      --invert-grep \
      --grep='^Release NiXOA [0-9]\+\.[0-9]\+\.[0-9]\+$' \
      --grep='^Start NiXOA [0-9]\+\.[0-9]\+\.[0-9]\+-dev\.[0-9]\+$')
    read -r version selected_bump < <(
      nixoa-ci-release-version "${last_tag#v}" "$REQUESTED_BUMP" <<<"$release_log"
    )
  fi

  tag=v${version}
  release_exists=false
  if release_state=$(gh release view "$tag" --json isDraft 2>/dev/null); then
    release_exists=true
    [[ $(jq -r .isDraft <<<"$release_state") == true ]] || {
      printf 'Release %s is already published.\n' "$tag" >&2
      return 1
    }
  fi
  if [[ $release_exists == false ]] \
    && git rev-parse --verify "refs/tags/${tag}" >/dev/null 2>&1; then
    printf 'Release tag %s already exists without a GitHub release.\n' "$tag" >&2
    return 1
  fi

  if [[ "$source_version" == "$version" ]]; then
    source_sha=$initial_sha
  else
    remote_sha=$(gh api "repos/${GITHUB_REPOSITORY}/commits/main" --jq .sha)
    [[ "$remote_sha" == "$initial_sha" ]]
    branch=automation/release-${tag}
    title="Release NiXOA ${version}"
    pr_number=$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --head "$branch" \
      --json number --jq '.[0].number // empty')
    if [[ -z "$pr_number" ]]; then
      if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        printf 'Release branch %s exists without an open pull request.\n' "$branch" >&2
        return 1
      fi
      git switch -c "$branch"
      printf '%s\n' "$version" >VERSION
      git config user.name github-actions[bot]
      git config user.email 41898282+github-actions[bot]@users.noreply.github.com
      git add VERSION
      git commit -m "$title"
      gh auth setup-git
      git push origin "HEAD:${branch}"
      pr_url=$(gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
        --title "$title" --body "Prepare the protected, immutable ${tag} release.")
      pr_number=$(gh pr view "$pr_url" --repo "$GITHUB_REPOSITORY" --json number --jq .number)
    fi
    export PR_NUMBER=$pr_number EXPECTED_BRANCH=$branch EXPECTED_TITLE=$title
    export EXPECTED_CHANGE_KIND=version EXPECTED_VERSION=$version VALIDATE_ONLY=true WAIT_FOR_MERGE=true
    nixoa-ci-trusted-update
    source_sha=$(gh pr view "$pr_number" --repo "$GITHUB_REPOSITORY" \
      --json mergeCommit --jq .mergeCommit.oid)
  fi

  remote_sha=$(gh api "repos/${GITHUB_REPOSITORY}/commits/main" --jq .sha)
  [[ "$remote_sha" == "$source_sha" ]] || {
    printf 'Main advanced before release publication; dispatch again.\n' >&2
    return 1
  }
  {
    printf 'source_sha=%s\n' "$source_sha"
    printf 'tag=%s\n' "$tag"
    printf 'version=%s\n' "$version"
  } >>"${GITHUB_OUTPUT:?}"
  printf 'Selected %s with a %s bump.\n' "$tag" "$selected_bump"
}

dispatch() {
  : "${GITHUB_REPOSITORY:?}" "${SOURCE_SHA:?}"
  remote_sha=$(gh api "repos/${GITHUB_REPOSITORY}/commits/main" --jq .sha)
  [[ "$remote_sha" == "$SOURCE_SHA" ]]
  previous_run_id=$(gh run list --workflow ci.yml --event workflow_dispatch --branch main \
    --commit "$SOURCE_SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
  gh workflow run ci.yml --ref main -f validate_only=false -f force_artifact=false
  run_id=
  for _ in {1..24}; do
    run_id=$(gh run list --workflow ci.yml --event workflow_dispatch --branch main \
      --commit "$SOURCE_SHA" --limit 5 --json databaseId \
      --jq ".[] | select((.databaseId | tostring) != \"${previous_run_id}\") | .databaseId" | head -n 1)
    [[ -z "$run_id" ]] || break
    sleep 5
  done
  [[ -n "$run_id" ]]
  gh run watch "$run_id" --exit-status
  printf 'run_id=%s\n' "$run_id" >>"${GITHUB_OUTPUT:?}"
}

inventory() {
  : "${SOURCE_SHA:?}"
  expected_build_input=$(nixoa-ci-build-input)
  jq -e --arg build_input "$expected_build_input" --arg source_commit "$SOURCE_SHA" \
    '.schema_version == 2 and .build_input == $build_input and .source_commit == $source_commit and (.artifact_run_id | type == "number")' \
    candidate-state/nixoa-build-state.json >/dev/null
  {
    printf 'artifact_run_id=%s\n' "$(jq -r .artifact_run_id candidate-state/nixoa-build-state.json)"
    printf 'artifact_source_commit=%s\n' "$(jq -r .artifact_source_commit candidate-state/nixoa-build-state.json)"
    printf 'build_input=%s\n' "$expected_build_input"
  } >>"${GITHUB_OUTPUT:?}"
}

verify() {
  : "${ARTIFACT_RUN_ID:?}" "${ARTIFACT_SOURCE_COMMIT:?}" "${BUILD_INPUT:?}" "${GITHUB_REPOSITORY:?}"
  (cd candidate && sha256sum --check --strict nixoa-installer.iso.sha256 \
    && sha256sum --check --strict nixoa-system.spdx.json.sha256 \
    && sha256sum --check --strict nixoa-system.cdx.json.sha256)
  jq -e --arg build_input "$BUILD_INPUT" --arg artifact_source_commit "$ARTIFACT_SOURCE_COMMIT" \
    --argjson artifact_run_id "$ARTIFACT_RUN_ID" \
    '.schema_version == 2 and .build_input == $build_input and .artifact_source_commit == $artifact_source_commit and .artifact_run_id == $artifact_run_id' \
    candidate/nixoa-build-state.json >/dev/null
  installer=candidate/result-installer/iso/nixoa-installer.iso
  signer_workflow="${GITHUB_REPOSITORY}/.github/workflows/ci.yml"
  gh attestation verify "$installer" --repo "$GITHUB_REPOSITORY" --signer-workflow "$signer_workflow" \
    --source-digest "$ARTIFACT_SOURCE_COMMIT" --deny-self-hosted-runners
  spdx_version=$(jq -er .spdxVersion candidate/nixoa-system.spdx.json)
  gh attestation verify "$installer" --repo "$GITHUB_REPOSITORY" --signer-workflow "$signer_workflow" \
    --source-digest "$ARTIFACT_SOURCE_COMMIT" \
    --predicate-type "https://spdx.dev/Document/v${spdx_version#SPDX-}" --deny-self-hosted-runners
}

stage() {
  : "${ARTIFACT_RUN_ID:?}" "${ARTIFACT_SOURCE_COMMIT:?}" "${BUILD_INPUT:?}"
  : "${RELEASE_TAG:?}" "${RELEASE_VERSION:?}" "${SOURCE_SHA:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}"
  [[ "$SOURCE_SHA" == "$(git rev-parse HEAD)" ]]
  [[ $(<VERSION) == "$RELEASE_VERSION" ]]
  install -d -m 0755 release
  versioned_installer="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nixoa-${RELEASE_TAG}.iso"
  nixoa-ci-release-stage candidate/result-installer/iso/nixoa-installer.iso "$versioned_installer" release
  gzip -9c candidate/nixoa-system.spdx.json >"release/nixoa-${RELEASE_TAG}.spdx.json.gz"
  gzip -9c candidate/nixoa-system.cdx.json >"release/nixoa-${RELEASE_TAG}.cdx.json.gz"
  (cd release && sha256sum "nixoa-${RELEASE_TAG}.spdx.json.gz" >"nixoa-${RELEASE_TAG}.spdx.json.gz.sha256" \
    && sha256sum "nixoa-${RELEASE_TAG}.cdx.json.gz" >"nixoa-${RELEASE_TAG}.cdx.json.gz.sha256")
  mapfile -t installer_parts < <(find release -maxdepth 1 -type f -name "nixoa-${RELEASE_TAG}.iso.part-*" -print | sort)
  installer_parts_json=$(for part in "${installer_parts[@]}"; do
    jq -n --arg name "${part##*/}" --arg sha256 "$(sha256sum "$part" | cut -d' ' -f1)" \
      '{name:$name,sha256:$sha256}'
  done | jq -s .)
  created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n --arg version "$RELEASE_VERSION" --arg tag "$RELEASE_TAG" --arg source_commit "$SOURCE_SHA" \
    --arg artifact_source_commit "$ARTIFACT_SOURCE_COMMIT" --arg build_input "$BUILD_INPUT" \
    --arg created_at "$created_at" --arg repository "$GITHUB_REPOSITORY" \
    --arg release_run "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" \
    --arg artifact_run "https://github.com/${GITHUB_REPOSITORY}/actions/runs/${ARTIFACT_RUN_ID}" \
    --arg installer "nixoa-${RELEASE_TAG}.iso" \
    --arg installer_sha256 "$(cut -d' ' -f1 "release/nixoa-${RELEASE_TAG}.iso.sha256")" \
    --argjson installer_parts "$installer_parts_json" --arg spdx "nixoa-${RELEASE_TAG}.spdx.json.gz" \
    --arg spdx_sha256 "$(cut -d' ' -f1 "release/nixoa-${RELEASE_TAG}.spdx.json.gz.sha256")" \
    --arg cdx "nixoa-${RELEASE_TAG}.cdx.json.gz" \
    --arg cdx_sha256 "$(cut -d' ' -f1 "release/nixoa-${RELEASE_TAG}.cdx.json.gz.sha256")" \
    '{schema_version:2,version:$version,tag:$tag,source_commit:$source_commit,artifact_source_commit:$artifact_source_commit,build_input:$build_input,created_at:$created_at,repository:$repository,release_run:$release_run,artifact_run:$artifact_run,assets:{installer:{name:$installer,sha256:$installer_sha256,parts:$installer_parts},spdx:{name:$spdx,sha256:$spdx_sha256},cyclonedx:{name:$cdx,sha256:$cdx_sha256}}}' \
    >release/release-manifest.json
  (cd release && sha256sum release-manifest.json >release-manifest.json.sha256)
}

draft() {
  : "${RELEASE_TAG:?}" "${RELEASE_VERSION:?}" "${SOURCE_SHA:?}"
  notes_file="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/release-notes.md"
  nixoa-ci-release-notes "$RELEASE_VERSION" CHANGELOG.md >"$notes_file"
  mapfile -t assets < <(find release -maxdepth 1 -type f -print | sort)
  mapfile -t installer_parts < <(find release -maxdepth 1 -type f -name "nixoa-${RELEASE_TAG}.iso.part-*" -print | sort)
  [[ ${#assets[@]} -eq $((${#installer_parts[@]} + 7)) ]]
  if release_state=$(gh release view "$RELEASE_TAG" --json isDraft,targetCommitish 2>/dev/null); then
    draft_target=$(jq -r .targetCommitish <<<"$release_state")
    if [[ $(jq -r .isDraft <<<"$release_state") == true ]]; then
      git merge-base --is-ancestor "$draft_target" "$SOURCE_SHA"
      gh release edit "$RELEASE_TAG" --notes-file "$notes_file" --target "$SOURCE_SHA"
      gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
    else
      [[ $(git rev-parse "$draft_target^{commit}") == "$SOURCE_SHA" ]]
    fi
  else
    gh release create "$RELEASE_TAG" "${assets[@]}" --draft --notes-file "$notes_file" \
      --target "$SOURCE_SHA" --title "NiXOA ${RELEASE_VERSION}"
  fi
  mapfile -t expected < <(printf '%s\n' "${assets[@]##*/}" | sort)
  mapfile -t actual < <(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name' | sort)
  [[ "${expected[*]}" == "${actual[*]}" ]]
}

publish() {
  : "${RELEASE_TAG:?}" "${SOURCE_SHA:?}"
  release_state=$(gh release view "$RELEASE_TAG" --json isDraft,targetCommitish)
  target=$(jq -er .targetCommitish <<<"$release_state")
  [[ $(git rev-parse "$target^{commit}") == "$SOURCE_SHA" ]]
  if [[ $(jq -r .isDraft <<<"$release_state") == true ]]; then
    gh release edit "$RELEASE_TAG" --draft=false --latest
  else
    printf 'Release %s is already published and immutable.\n' "$RELEASE_TAG"
  fi
}

advance() {
  : "${RELEASE_VERSION:?}" "${GITHUB_REPOSITORY:?}" "${DEFAULT_BRANCH:?}" "${EXPECTED_AUTHOR:?}"
  IFS=. read -r major minor patch <<<"$RELEASE_VERSION"
  next_version="${major}.${minor}.$((patch + 1))-dev.0"
  current_version=$(<VERSION)
  [[ "$current_version" == "$RELEASE_VERSION" || "$current_version" == "$next_version" ]]
  [[ "$current_version" == "$next_version" ]] && return 0
  branch=automation/start-${next_version}
  title="Start NiXOA ${next_version}"
  pr_number=$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --head "$branch" \
    --json number --jq '.[0].number // empty')
  if [[ -z "$pr_number" ]]; then
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      printf 'Development branch %s exists without an open pull request.\n' "$branch" >&2
      return 1
    fi
    git switch -c "$branch"
    printf '%s\n' "$next_version" >VERSION
    git config user.name github-actions[bot]
    git config user.email 41898282+github-actions[bot]@users.noreply.github.com
    git add VERSION
    git commit -m "$title"
    gh auth setup-git
    git push origin "HEAD:${branch}"
    pr_url=$(gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" --title "$title" \
      --body "Advance development after the immutable v${RELEASE_VERSION} release.")
    pr_number=$(gh pr view "$pr_url" --repo "$GITHUB_REPOSITORY" --json number --jq .number)
  fi
  export PR_NUMBER=$pr_number EXPECTED_BRANCH=$branch EXPECTED_TITLE=$title
  export EXPECTED_CHANGE_KIND=version EXPECTED_VERSION=$next_version VALIDATE_ONLY=true WAIT_FOR_MERGE=true
  nixoa-ci-trusted-update
}

case "${1:-}" in
  prepare|dispatch|inventory|verify|stage|draft|publish|advance)
    operation=$1
    shift
    "$operation" "$@"
    ;;
  *)
    printf 'usage: nixoa-ci-release-manager prepare|dispatch|inventory|verify|stage|draft|publish|advance\n' >&2
    exit 2
    ;;
esac
