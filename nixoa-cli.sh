#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# NiXOA host CLI

set -euo pipefail

VERSION="3.2.0"

if [ -n "${NIXOA_SYSTEM_ROOT:-}" ]; then
  REPO_ROOT="$NIXOA_SYSTEM_ROOT"
elif [ -n "${SUDO_USER:-}" ]; then
  REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  REPO_ROOT="${REAL_HOME}/nixoa"
else
  REPO_ROOT="${HOME}/nixoa"
fi

if [ ! -f "$REPO_ROOT/scripts/lib/common.sh" ]; then
  echo "error: NiXOA checkout not found at $REPO_ROOT" >&2
  exit 1
fi

. "$REPO_ROOT/scripts/lib/common.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_error() { printf '%b\n' "${RED}error:${NC} $1" >&2; }
print_info() { printf '%b\n' "${BLUE}info:${NC} $1"; }
print_success() { printf '%b\n' "${GREEN}ok:${NC} $1"; }
print_warning() { printf '%b\n' "${YELLOW}warn:${NC} $1"; }

ensure_config_dir() {
  if [ ! -d "$REPO_ROOT" ]; then
    print_error "Checkout not found at $REPO_ROOT"
    exit 1
  fi
}

ensure_git_repo() {
  if [ ! -d "$REPO_ROOT/.git" ]; then
    print_error "No git repository found at $REPO_ROOT"
    exit 1
  fi
}

default_hostname() {
  nixoa_default_hostname
}

show_usage() {
  cat <<EOF
NiXOA CLI v${VERSION}

Usage:
  nixoa <command> [options]

Commands:
  config commit [message]         Commit NiXOA repository changes
  config apply [--first-install]  Apply the current host configuration
  config show                     Show repository diffs
  config diff                     Alias for config show
  config history                  Show repository history
  config edit                     Edit the active host files
  config status                   Show git status for the NiXOA repo
  rebuild [switch|build]          Run the active host through apply-config.sh
  update                          Run nix flake update in the NiXOA repo
  rollback                        Roll back to the previous NixOS generation
  list-generations                List NixOS generations
  status                          Show host and service status
  version                         Show CLI and NixOS version
  help                            Show this message
EOF
}

config_commit() {
  ensure_config_dir
  "$REPO_ROOT/scripts/commit-config.sh" "$@"
}

config_apply() {
  ensure_config_dir
  "$REPO_ROOT/scripts/apply-config.sh" "$@"
}

config_show() {
  ensure_config_dir
  "$REPO_ROOT/scripts/show-diff.sh"
}

config_history() {
  ensure_config_dir
  "$REPO_ROOT/scripts/history.sh"
}

config_edit() {
  ensure_config_dir
  local editor="${EDITOR:-nano}"
  local host="${1:-$(default_hostname)}"

  exec "$editor" \
    "$(nixoa_host_settings_file "$host")" \
    "$(nixoa_host_menu_file "$host")" \
    "$REPO_ROOT/config.nixoa.toml"
}

config_status() {
  ensure_config_dir
  ensure_git_repo
  git -C "$REPO_ROOT" status -- "${NIXOA_TRACKED_PATHS[@]}"
}

rebuild_system() {
  ensure_config_dir

  local mode="${1:-switch}"
  case "$mode" in
    switch)
      exec "$REPO_ROOT/scripts/apply-config.sh" --hostname "$(default_hostname)"
      ;;
    build)
      exec "$REPO_ROOT/scripts/apply-config.sh" --hostname "$(default_hostname)" --build
      ;;
    *)
      print_error "Invalid rebuild mode: $mode"
      exit 1
      ;;
  esac
}

update_flake() {
  ensure_config_dir
  ensure_git_repo

  print_info "Updating flake inputs in $REPO_ROOT"
  (
    cd "$REPO_ROOT"
    nix flake update
  )
  print_success "Flake inputs updated"
  print_info "Apply with: $REPO_ROOT/scripts/apply-config.sh --hostname $(default_hostname)"
}

rollback_system() {
  exec "$REPO_ROOT/scripts/apply-config.sh" --hostname "$(default_hostname)" --rollback
}

list_generations() {
  exec sudo nix-env --list-generations -p /nix/var/nix/profiles/system
}

show_status() {
  ensure_config_dir

  echo "Host: $(hostname)"
  echo "NixOS: $(nixos-version)"
  echo "Config: $REPO_ROOT"
  echo "Active host: $(default_hostname)"
  echo ""
  echo "Services:"
  systemctl is-active xo-server.service >/dev/null 2>&1 && echo "  xo-server: active" || echo "  xo-server: inactive"
  systemctl is-active redis-xo.service >/dev/null 2>&1 && echo "  redis-xo: active" || echo "  redis-xo: inactive"

  if [ -d "$REPO_ROOT/.git" ]; then
    echo ""
    echo "Repository:"
    git -C "$REPO_ROOT" status --short -- "${NIXOA_TRACKED_PATHS[@]}"
  fi
}

show_version() {
  echo "NiXOA CLI v${VERSION}"
  echo "NixOS Version: $(nixos-version)"
}

main() {
  if [ $# -eq 0 ]; then
    show_usage
    exit 0
  fi

  case "$1" in
    config)
      shift
      case "${1:-}" in
        commit)
          shift
          config_commit "$@"
          ;;
        apply)
          shift
          config_apply "$@"
          ;;
        show|diff)
          config_show
          ;;
        history)
          config_history
          ;;
        edit)
          shift
          config_edit "$@"
          ;;
        status)
          config_status
          ;;
        *)
          show_usage
          exit 1
          ;;
      esac
      ;;
    rebuild)
      shift
      rebuild_system "${1:-switch}"
      ;;
    update)
      update_flake
      ;;
    rollback)
      rollback_system
      ;;
    list-generations)
      list_generations
      ;;
    status)
      show_status
      ;;
    version)
      show_version
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      print_error "Unknown command: $1"
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
