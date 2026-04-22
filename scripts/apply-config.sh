#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Apply, build, boot, or roll back the NiXOA configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: apply-config.sh [--target TARGET | --hostname TARGET] [--build | --boot | --dry-run | --rollback] [--first-install] [--ask] [--cores N] [--verbose] [--no-nom] [-- extra nh build args...]

Options:
  --target TARGET       Canonical target selector. Accepts <hostname>, <hostname>-vm, or vm.
  --hostname TARGET     Legacy alias for --target.
  --build               Build without switching.
  --boot                Build and activate on the next reboot.
  --dry-run             Preview the apply flow without mutating the system.
  --rollback            Roll back the current system generation.
  --first-install       Add Determinate first-install cache flags for the initial switch.
  --ask                 Ask nh for confirmation before mutating actions.
  --cores N             Pass through the requested core count to nh.
  --verbose             Increase nh verbosity.
  --no-nom              Disable nix-output-monitor integration in nh.
  --help                Show this help text.
EOF
}

target_arg="${NIXOA_HOSTNAME:-$(nixoa_default_target)}"
rebuild_action="switch"
record_action="switch"
first_install=0
rollback=0
dry_run=0
ask=0
verbose=0
no_nom=0
cores=""
declare -a extra_args=()
declare -a build_extra_args=()

while [ $# -gt 0 ]; do
  case "$1" in
    --target|--hostname)
      target_arg="$2"
      shift 2
      ;;
    --build)
      rebuild_action="build"
      record_action="build"
      shift
      ;;
    --boot)
      rebuild_action="boot"
      record_action="boot"
      shift
      ;;
    --dry-run)
      rebuild_action="switch"
      record_action="dry-run"
      dry_run=1
      shift
      ;;
    --rollback)
      rollback=1
      rebuild_action="switch"
      record_action="rollback"
      shift
      ;;
    --first-install)
      first_install=1
      shift
      ;;
    --ask)
      ask=1
      shift
      ;;
    --cores)
      cores="$2"
      shift 2
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    --no-nom)
      no_nom=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

nixoa_cd_root
target_arg="$(nixoa_require_target_output "$target_arg")"

if [ "$rollback" -eq 1 ]; then
  if [ "$ask" -eq 1 ] && ! nixoa_confirm "Roll back the current system generation"; then
    nixoa_print_warning "Rollback cancelled."
    exit 1
  fi
else
  if nixoa_has_changes; then
    nixoa_print_warning "Tracked NiXOA files are dirty; proceeding with the current working tree."
  fi
fi

current_head="$(git -C "$NIXOA_SYSTEM_ROOT" rev-parse HEAD 2>/dev/null || true)"

if [ "$first_install" -eq 1 ]; then
  build_extra_args+=(
    --option
    extra-experimental-features
    "nix-command flakes"
    --option
    extra-substituters
    "https://install.determinate.systems"
    --option
    extra-trusted-public-keys
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
  )
fi

build_extra_args+=("${extra_args[@]}")

if [ "$rollback" -eq 1 ]; then
  rebuild_cmd=(
    nixos-rebuild
    switch
    --rollback
    -L
  )
else
  nixoa_build_nh_command rebuild_cmd "$rebuild_action" "$target_arg" "$ask" "$cores" "$verbose" "$no_nom"
  if [ "$dry_run" -eq 1 ]; then
    rebuild_cmd+=(--dry)
  fi
  if [ "${#build_extra_args[@]}" -gt 0 ]; then
    rebuild_cmd+=(-- "${build_extra_args[@]}")
  fi
fi

printf 'Running:'
if [ "$rollback" -eq 0 ]; then
  printf ' %q' nh
else
  if [ "$EUID" -ne 0 ]; then
    sudo_bin="$(nixoa_sudo_bin)" || exit 1
    rebuild_cmd=("$sudo_bin" "${rebuild_cmd[@]}")
  fi
fi
printf ' %q' "${rebuild_cmd[@]}"
printf '\n'

if [ "$rollback" -eq 1 ]; then
  run_rebuild=("${rebuild_cmd[@]}")
else
  run_rebuild=(nixoa_run_nh "${rebuild_cmd[@]}")
fi

if "${run_rebuild[@]}"; then
  nixoa_write_apply_state "success" "$record_action" "$target_arg" "$current_head" "$first_install" "0"
else
  exit_code="$?"
  nixoa_write_apply_state "failed" "$record_action" "$target_arg" "$current_head" "$first_install" "$exit_code"
  exit "$exit_code"
fi
