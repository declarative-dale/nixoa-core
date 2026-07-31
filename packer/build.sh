#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PACKER_BIN=${PACKER_BIN:-packer-xenserver}
NIX_BIN=${NIX_BIN:-nix}
OPERATOR_PUBLIC_KEY_FILE=${OPERATOR_PUBLIC_KEY_FILE:-${HOME:-}/.ssh/id_ed25519.pub}
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/output}
INSTALLER_ISO=${INSTALLER_ISO:-$OUTPUT_DIR/nixoa-installer.iso}
BUILD_INSTALLER=${BUILD_INSTALLER:-1}

case "$BUILD_INSTALLER" in
  0|1) ;;
  *)
    printf 'BUILD_INSTALLER must be 1 or 0.\n' >&2
    exit 1
    ;;
esac

command -v "$PACKER_BIN" >/dev/null 2>&1 || {
  printf 'Packer executable not found: %s\n' "$PACKER_BIN" >&2
  exit 1
}
command -v "$NIX_BIN" >/dev/null 2>&1 || {
  printf 'Nix executable not found: %s\n' "$NIX_BIN" >&2
  exit 1
}
[[ -r "$OPERATOR_PUBLIC_KEY_FILE" ]] || {
  printf 'Operator SSH public key not found: %s\n' \
    "$OPERATOR_PUBLIC_KEY_FILE" >&2
  exit 1
}

if [[ "$BUILD_INSTALLER" == 1 ]]; then
  installer_result=$(
    "$NIX_BIN" build \
      "path:$REPO_ROOT#installer-iso" \
      --no-link \
      --print-out-paths
  )
  [[ -n "$installer_result" && "$installer_result" != *$'\n'* ]] || {
    printf 'Nix returned an invalid installer output path.\n' >&2
    exit 1
  }

  mkdir -p "$OUTPUT_DIR"
  installer_tmp="$INSTALLER_ISO.tmp"
  cleanup_installer() {
    rm -f -- "$installer_tmp"
  }
  trap cleanup_installer EXIT HUP INT TERM
  cp --reflink=auto \
    "$installer_result/iso/nixoa-installer.iso" \
    "$installer_tmp"
  chmod 0644 "$installer_tmp"
  mv -f "$installer_tmp" "$INSTALLER_ISO"
  trap - EXIT HUP INT TERM
fi

installer_iso="$INSTALLER_ISO"
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
