#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PACKER_BIN=${PACKER_BIN:-packer-xenserver}
NIX_BIN=${NIX_BIN:-nix}
GH_BIN=${GH_BIN:-gh}
OPERATOR_PUBLIC_KEY_FILE=${OPERATOR_PUBLIC_KEY_FILE:-${HOME:-}/.ssh/id_ed25519.pub}
INSTALLER_ISO=${INSTALLER_ISO:-}
INSTALLER_SOURCE=${INSTALLER_SOURCE:-github}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-declarative-dale/nixoa-core}
GITHUB_WORKFLOW=${GITHUB_WORKFLOW:-cache-nixoa-menu.yml}
GITHUB_BRANCH=${GITHUB_BRANCH:-main}
GITHUB_ARTIFACT_NAME=${GITHUB_ARTIFACT_NAME:-nixoa-installer}

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
    run_id=$(
      "$GH_BIN" run list \
        --repo "$GITHUB_REPOSITORY" \
        --workflow "$GITHUB_WORKFLOW" \
        --branch "$GITHUB_BRANCH" \
        --status success \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId'
    )
    [[ "$run_id" =~ ^[0-9]+$ ]] || {
      printf 'No successful NiXOA installer workflow run was found.\n' >&2
      exit 1
    }
    artifact_dir=$(mktemp -d "${TMPDIR:-/tmp}/nixoa-installer.XXXXXX")
    "$GH_BIN" run download "$run_id" \
      --repo "$GITHUB_REPOSITORY" \
      --name "$GITHUB_ARTIFACT_NAME" \
      --dir "$artifact_dir"
    installer_iso="$artifact_dir/result-installer/iso/nixoa-installer.iso"
    (
      cd "$artifact_dir"
      sha256sum --check --strict nixoa-installer.iso.sha256
    )
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
