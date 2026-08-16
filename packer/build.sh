#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PACKER_BIN=${PACKER_BIN:-packer-xenserver}
NIX_BIN=${NIX_BIN:-nix}
GH_BIN=${GH_BIN:-gh}
JQ_BIN=${JQ_BIN:-jq}
OPERATOR_PUBLIC_KEY_FILE=${OPERATOR_PUBLIC_KEY_FILE:-${HOME:-}/.ssh/id_ed25519.pub}
INSTALLER_ISO=${INSTALLER_ISO:-}
INSTALLER_SOURCE=${INSTALLER_SOURCE:-github}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-declarative-dale/nixoa-core}
GITHUB_WORKFLOW=${GITHUB_WORKFLOW:-ci.yml}
GITHUB_BRANCH=${GITHUB_BRANCH:-main}
GITHUB_ARTIFACT_NAME=${GITHUB_ARTIFACT_NAME:-nixoa-installer}
GITHUB_STATE_ARTIFACT_NAME=${GITHUB_STATE_ARTIFACT_NAME:-nixoa-build-state}

if [[ ${BUILD_INSTALLER+x} ]]; then
  case "$BUILD_INSTALLER" in
    0) INSTALLER_SOURCE=local ;;
    1) INSTALLER_SOURCE=build ;;
    *)
      printf 'BUILD_INSTALLER must be 1 or 0.\n' >&2
      exit 1
      ;;
  esac
fi
if [[ -n "$INSTALLER_ISO" ]]; then
  INSTALLER_SOURCE=local
fi

case "$INSTALLER_SOURCE" in
  github|build|local) ;;
  *)
    printf 'INSTALLER_SOURCE must be github, build, or local.\n' >&2
    exit 1
    ;;
esac

command -v "$PACKER_BIN" >/dev/null 2>&1 || {
  printf 'Packer executable not found: %s\n' "$PACKER_BIN" >&2
  exit 1
}
[[ -r "$OPERATOR_PUBLIC_KEY_FILE" ]] || {
  printf 'Operator SSH public key not found: %s\n' \
    "$OPERATOR_PUBLIC_KEY_FILE" >&2
  exit 1
}

artifact_dir=
cleanup() {
  [[ -z "$artifact_dir" ]] || rm -rf -- "$artifact_dir"
}
trap cleanup EXIT HUP INT TERM

case "$INSTALLER_SOURCE" in
  github)
    command -v "$GH_BIN" >/dev/null 2>&1 || {
      printf 'GitHub CLI executable not found: %s\n' "$GH_BIN" >&2
      exit 1
    }
    mapfile -t run_ids < <(
      "$GH_BIN" run list \
        --repo "$GITHUB_REPOSITORY" \
        --workflow "$GITHUB_WORKFLOW" \
        --branch "$GITHUB_BRANCH" \
        --status success \
        --limit 20 \
        --json databaseId \
        --jq '.[].databaseId'
    )
    [[ ${#run_ids[@]} -gt 0 ]] || {
      printf 'No successful NiXOA installer workflow run was found.\n' >&2
      exit 1
    }
    for run_id in "${run_ids[@]}"; do
      [[ "$run_id" =~ ^[0-9]+$ ]] || continue
      artifact_run_id=$run_id
      expected_build_input=
      state_dir=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-state.XXXXXX")
      if "$GH_BIN" run download "$run_id" \
        --repo "$GITHUB_REPOSITORY" \
        --name "$GITHUB_STATE_ARTIFACT_NAME" \
        --dir "$state_dir" >/dev/null 2>&1; then
        command -v "$JQ_BIN" >/dev/null 2>&1 || {
          printf 'jq is required to verify installer artifact state.\n' >&2
          exit 1
        }
        if ! "$JQ_BIN" -e \
          '.schema_version == 2 and (.artifact_run_id | type == "number") and (.build_input | type == "string")' \
          "$state_dir/nixoa-build-state.json" >/dev/null; then
          rm -rf -- "$state_dir"
          continue
        fi
        artifact_run_id=$("$JQ_BIN" -r .artifact_run_id \
          "$state_dir/nixoa-build-state.json")
        expected_build_input=$("$JQ_BIN" -r .build_input \
          "$state_dir/nixoa-build-state.json")
      fi
      rm -rf -- "$state_dir"

      candidate_dir=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-installer.XXXXXX")
      if "$GH_BIN" run download "$artifact_run_id" \
        --repo "$GITHUB_REPOSITORY" \
        --name "$GITHUB_ARTIFACT_NAME" \
        --dir "$candidate_dir" >/dev/null 2>&1 &&
        (
          cd "$candidate_dir"
          sha256sum --check --strict nixoa-installer.iso.sha256
        ); then
        # jq variables are intentionally protected from the shell.
        # shellcheck disable=SC2016
        if [[ -n "$expected_build_input" ]] &&
          ! "$JQ_BIN" -e \
            --arg build_input "$expected_build_input" \
            --argjson artifact_run_id "$artifact_run_id" \
            '.schema_version == 2 and .build_input == $build_input and .artifact_run_id == $artifact_run_id' \
            "$candidate_dir/nixoa-build-state.json" >/dev/null; then
          rm -rf -- "$candidate_dir"
          continue
        fi
        artifact_dir=$candidate_dir
        installer_iso="$artifact_dir/result-installer/iso/nixoa-installer.iso"
        break
      fi
      rm -rf -- "$candidate_dir"
    done
    [[ -n "$artifact_dir" ]] || {
      printf 'No valid immutable NiXOA installer artifact was found.\n' >&2
      exit 1
    }
    ;;
  build)
    command -v "$NIX_BIN" >/dev/null 2>&1 || {
      printf 'Nix executable not found: %s\n' "$NIX_BIN" >&2
      exit 1
    }
    installer_result=$(
      "$NIX_BIN" build \
        "path:$REPO_ROOT#installer-iso" \
        --accept-flake-config \
        --no-link \
        --print-out-paths
    )
    [[ -n "$installer_result" && "$installer_result" != *$'\n'* ]] || {
      printf 'Nix returned an invalid installer output path.\n' >&2
      exit 1
    }
    installer_iso="$installer_result/iso/nixoa-installer.iso"
    ;;
  local)
    installer_iso=${INSTALLER_ISO:-$REPO_ROOT/output/nixoa-installer.iso}
    ;;
esac

[[ -s "$installer_iso" ]] || {
  printf 'Installer ISO does not exist or is empty: %s\n' "$installer_iso" >&2
  exit 1
}
installer_iso=$(realpath "$installer_iso")
installer_sha256=$(sha256sum "$installer_iso" | awk '{print $1}')
operator_key=$(realpath "$OPERATOR_PUBLIC_KEY_FILE")
printf 'Installer ISO: %s\n' "$installer_iso"

cd "$SCRIPT_DIR"
"$PACKER_BIN" init .
"$PACKER_BIN" build \
  -parallel-builds=1 \
  -var "iso_url=$installer_iso" \
  -var "iso_checksum=sha256:$installer_sha256" \
  -var "operator_public_key_file=$operator_key" \
  "$@" \
  .
