#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# NiXOA host CLI

set -euo pipefail

VERSION="1.3.0"

if [ -n "${SUDO_USER:-}" ]; then
  REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  CONFIG_DIR="${REAL_HOME}/system"
else
  CONFIG_DIR="${HOME}/system"
fi

TRACKED_PATHS=(
  config
  config.nixoa.toml
  docs
  flake.lock
  flake.nix
  hardware-configuration.nix
  modules
  scripts
  README.md
  AGENTS.md
)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_error() { printf '%b\n' "${RED}error:${NC} $1" >&2; }
print_info() { printf '%b\n' "${BLUE}info:${NC} $1"; }
print_success() { printf '%b\n' "${GREEN}ok:${NC} $1"; }
print_warning() { printf '%b\n' "${YELLOW}warn:${NC} $1"; }

default_hostname() {
  hostname -s 2>/dev/null || printf '%s\n' "nixoa"
}

ensure_config_dir() {
  if [ ! -d "$CONFIG_DIR" ]; then
    print_error "System checkout not found at $CONFIG_DIR"
    exit 1
  fi
}

ensure_git_repo() {
  if [ ! -d "$CONFIG_DIR/.git" ]; then
    print_error "No git repository found at $CONFIG_DIR"
    exit 1
  fi
}

run_config_script() {
  local script="$1"
  shift
  ensure_config_dir
  exec "$CONFIG_DIR/scripts/$script" "$@"
}

show_usage() {
  cat <<EOF
NiXOA CLI v${VERSION}

Usage:
  nixoa <command> [options]

Commands:
  config commit <message>          Commit system repository changes
  config apply [--first-install]   Apply the current host configuration
  config show                      Show repository diffs
  config diff                      Alias for config show
  config history                   Show repository history
  config edit                      Edit the common config fragments
  config status                    Show git status for the system repo
  rebuild [switch|test|boot]       Run nixos-rebuild against the system flake
  update                           Run nix flake update in the system repo
  rollback                         Roll back to the previous NixOS generation
  list-generations                 List NixOS generations
  status                           Show host and service status
  version                          Show CLI and NixOS version
  help                             Show this message
EOF
}

config_commit() {
  if [ $# -eq 0 ]; then
    print_error "Commit message required"
    exit 1
  fi

  ensure_config_dir
  "$CONFIG_DIR/scripts/commit-config.sh" "$1"
}

config_apply() {
  ensure_config_dir
  "$CONFIG_DIR/scripts/apply-config.sh" --hostname "$(default_hostname)" "$@"
}

config_show() {
  ensure_config_dir
  "$CONFIG_DIR/scripts/show-diff.sh"
}

config_history() {
  ensure_config_dir
  "$CONFIG_DIR/scripts/history.sh"
}

config_edit() {
  ensure_config_dir
  local editor="${EDITOR:-nano}"
  local files=(
    "$CONFIG_DIR/config/site.nix"
    "$CONFIG_DIR/config/platform.nix"
    "$CONFIG_DIR/config/features.nix"
    "$CONFIG_DIR/config/packages.nix"
    "$CONFIG_DIR/config/xo.nix"
    "$CONFIG_DIR/config/storage.nix"
  )

  if [ -f "$CONFIG_DIR/config/overrides.nix" ]; then
    files+=("$CONFIG_DIR/config/overrides.nix")
  fi

  exec "$editor" "${files[@]}"
}

config_status() {
  ensure_config_dir
  ensure_git_repo
  git -C "$CONFIG_DIR" status -- "${TRACKED_PATHS[@]}"
}

rebuild_system() {
  ensure_config_dir

  local mode="${1:-switch}"
  case "$mode" in
    switch|test|boot)
      ;;
    *)
      print_error "Invalid rebuild mode: $mode"
      exit 1
      ;;
  esac

  exec sudo nixos-rebuild "$mode" --flake "$CONFIG_DIR#$(default_hostname)" -L
}

update_flake() {
  ensure_config_dir
  ensure_git_repo

  print_info "Updating flake inputs in $CONFIG_DIR"
  (
    cd "$CONFIG_DIR"
    nix flake update
  )
  print_success "Flake inputs updated"
  print_info "Apply with: $CONFIG_DIR/scripts/apply-config.sh --hostname $(default_hostname)"
}

rollback_system() {
  exec sudo nixos-rebuild switch --rollback
}

list_generations() {
  exec sudo nix-env --list-generations -p /nix/var/nix/profiles/system
}

show_status() {
  ensure_config_dir

  echo "Host: $(hostname)"
  echo "NixOS: $(nixos-version)"
  echo "Config: $CONFIG_DIR"
  echo ""
  echo "Services:"
  systemctl is-active xo-server.service >/dev/null 2>&1 && echo "  xo-server: active" || echo "  xo-server: inactive"
  systemctl is-active redis-xo.service >/dev/null 2>&1 && echo "  redis-xo: active" || echo "  redis-xo: inactive"

  if [ -d "$CONFIG_DIR/.git" ]; then
    echo ""
    echo "Repository:"
    git -C "$CONFIG_DIR" status --short -- "${TRACKED_PATHS[@]}"
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
          config_edit
          ;;
        status)
          config_status
          ;;
        help|"")
          show_usage
          ;;
        *)
          print_error "Unknown config subcommand: $1"
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
    list-generations|generations)
      list_generations
      ;;
    status)
      show_status
      ;;
    version|--version|-v)
      show_version
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      print_error "Unknown command: $1"
      exit 1
      ;;
  esac
}

main "$@"
