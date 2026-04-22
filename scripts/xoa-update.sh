#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: xoa-update.sh [--target TARGET | --hostname TARGET] [--ask]
EOF
}

target_arg="$(nixoa_default_target)"
ask=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target|--hostname)
      target_arg="$2"
      shift 2
      ;;
    --ask)
      ask=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      nixoa_print_error "Unknown xoa update option: $1"
      exit 1
      ;;
  esac
done

nixoa_cd_root
target_arg="$(nixoa_require_target_output "$target_arg")"

if [ "$ask" -eq 1 ] && ! nixoa_confirm "Update the xen-orchestra-ce flake input"; then
  nixoa_print_warning "XOA update cancelled."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  nixoa_print_error "jq is required for xoa-update.sh."
  exit 1
fi

old_rev="$(jq -r '.nodes."xen-orchestra-ce".locked.rev // empty' flake.lock 2>/dev/null || true)"

nixoa_print_info "Updating xen-orchestra-ce input"
nix flake lock --update-input xen-orchestra-ce --commit-lock-file

new_rev="$(jq -r '.nodes."xen-orchestra-ce".locked.rev // empty' flake.lock)"
if [ -z "$new_rev" ]; then
  nixoa_print_error "Could not read the new xen-orchestra-ce revision from flake.lock."
  exit 1
fi

printf 'xen-orchestra-ce: %s -> %s\n' "${old_rev:-<none>}" "$new_rev"

if [ -n "$old_rev" ] && [ "$old_rev" != "$new_rev" ]; then
  echo
  echo "Best-effort commit log between revisions:"
  tmp_dir="$(mktemp -d)"
  git clone --depth 1 https://codeberg.org/NiXOA/xen-orchestra-ce.git "$tmp_dir" >/dev/null 2>&1 || true
  if git -C "$tmp_dir" fetch --depth 100 origin "$new_rev" >/dev/null 2>&1 \
    && git -C "$tmp_dir" fetch --depth 100 origin "$old_rev" >/dev/null 2>&1
  then
    git -C "$tmp_dir" log --oneline "${old_rev}..${new_rev}" || true
  else
    echo "(Skipping commit log; remote fetch was not available.)"
  fi
  rm -rf "$tmp_dir"
fi

echo
nixoa_print_success "Updated xen-orchestra-ce."
nixoa_print_cli_command "Next:" apply --target "$target_arg"
nixoa_print_cli_command "Safer path:" boot --target "$target_arg"
