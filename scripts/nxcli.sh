#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Canonical NiXOA operator CLI

set -euo pipefail

readonly NXCLI_VERSION="5.0.0"

resolve_repo_root() {
  local candidate search_dir script_dir git_root

  if [ -n "${NIXOA_SYSTEM_ROOT:-}" ] && [ -f "$NIXOA_SYSTEM_ROOT/scripts/lib/common.sh" ]; then
    printf '%s\n' "$NIXOA_SYSTEM_ROOT"
    return
  fi

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  candidate="$(cd "$script_dir/.." && pwd)"
  if [ -f "$candidate/scripts/lib/common.sh" ]; then
    printf '%s\n' "$candidate"
    return
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    && [ -f "$git_root/scripts/lib/common.sh" ]
  then
    printf '%s\n' "$git_root"
    return
  fi

  search_dir="${PWD:-}"
  while [ -n "$search_dir" ] && [ "$search_dir" != / ]; do
    if [ -f "$search_dir/scripts/lib/common.sh" ]; then
      printf '%s\n' "$search_dir"
      return
    fi
    search_dir="$(dirname "$search_dir")"
  done

  nixoa_root_error="Could not find a NiXOA checkout. Run from it or set NIXOA_SYSTEM_ROOT."
  printf 'error: %s\n' "$nixoa_root_error" >&2
  exit 1
}

REPO_ROOT="$(resolve_repo_root)"
export NIXOA_SYSTEM_ROOT="$REPO_ROOT"
# shellcheck source=scripts/lib/common.sh
. "$REPO_ROOT/scripts/lib/common.sh"

show_help() {
  cat <<'EOF'
Usage:
  nxcli help
  nxcli version
  nxcli status [--json]
  nxcli apply [--build|--dry-run|--first-install] [--ask] [--cores N] [--verbose] [-- ...]
  nxcli boot [--ask] [--cores N] [--verbose] [-- ...]
  nxcli rollback [--ask]
  nxcli commit [MESSAGE]
  nxcli diff [--json|--staged]
  nxcli history
  nxcli host show [--json]
  nxcli host edit
  nxcli host development-mode [status|on|off|toggle]
  nxcli update flake [--preview] [--ask]
  nxcli update xoa [--preview] [--ask]
  nxcli xo logs
  nxcli generations list

NiXOA has one canonical flake target: .#nixoa.
EOF
}

show_apply_help() {
  cat <<'EOF'
Usage: nxcli apply [--build|--dry-run|--first-install] [--ask] [--cores N] [--verbose] [-- ...]
       nxcli boot [--ask] [--cores N] [--verbose] [-- ...]
       nxcli rollback [--ask]

All operations target .#nixoa. Target-selection flags are intentionally unsupported.
EOF
}

show_update_help() {
  cat <<'EOF'
Usage: nxcli update flake [--preview] [--ask]
       nxcli update xoa [--preview] [--ask]
EOF
}

json_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g')"
}

show_diff_json() {
  local first=1 line status path
  printf '{\n  "changes": ['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    status="${line:0:2}"
    path="${line:3}"
    [ "$first" -eq 1 ] || printf ','
    printf '\n    {"status": %s, "path": %s}' "$(json_quote "$status")" "$(json_quote "$path")"
    first=0
  done < <(nixoa_status_porcelain || true)
  [ "$first" -eq 1 ] || printf '\n  '
  printf ']\n}\n'
}

show_status() {
  case "${1:-}" in
    "")
      nixoa_render_status
      ;;
    --json)
      "$NIXOA_SYSTEM_ROOT/scripts/tui/state.sh" --json
      ;;
    --help|-h)
      printf 'Usage: nxcli status [--json]\n'
      ;;
    *)
      nixoa_print_error "Unknown status option: $1"
      return 1
      ;;
  esac
}

host_show() {
  local json=0 development=false
  case "${1:-}" in
    "") ;;
    --json) json=1 ;;
    --help|-h)
      printf 'Usage: nxcli host show [--json]\n'
      return
      ;;
    *)
      nixoa_print_error "host show does not accept a target; NiXOA always uses nixoa."
      return 1
      ;;
  esac
  development="$(
    sed -nE 's/^[[:space:]]*developmentMode[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*;.*/\1/p' \
      "$NIXOA_MENU_FILE" "$NIXOA_SETTINGS_FILE" | head -n 1
  )"
  development="${development:-false}"
  if [ "$json" -eq 1 ]; then
    printf '{\n'
    printf '  "host": "nixoa",\n'
    printf '  "target": "nixoa",\n'
    printf '  "directory": "host",\n'
    printf '  "username": "nixoa",\n'
    printf '  "hostname": %s,\n' "$(json_quote "$(nixoa_default_hostname)")"
    printf '  "developmentMode": %s,\n' "$development"
    printf '  "settingsFile": "host/settings.nix",\n'
    printf '  "menuFile": "host/menu.nix",\n'
    printf '  "hardwareFile": "host/hardware-configuration.nix"\n'
    printf '}\n'
  else
    printf 'Host: nixoa\n'
    printf 'Target: .#nixoa\n'
    printf 'Hostname: %s\n' "$(nixoa_default_hostname)"
    printf 'Operator: nixoa\n'
    printf 'Development Mode: %s\n' "$development"
    printf 'Settings: host/settings.nix\n'
    printf 'Menu overrides: host/menu.nix\n'
    printf 'Hardware: host/hardware-configuration.nix\n'
  fi
}

host_development_mode() {
  local mode="${1:-status}" value
  case "$mode" in
    status)
      value="$(
        sed -nE 's/^[[:space:]]*developmentMode[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*;.*/\1/p' \
          "$NIXOA_MENU_FILE" "$NIXOA_SETTINGS_FILE" | head -n 1
      )"
      printf 'Development Mode for nixoa: %s\n' "${value:-false}"
      ;;
    on|enable|true)
      "$NIXOA_SYSTEM_ROOT/scripts/tui/action.sh" set-development-mode true
      ;;
    off|disable|false)
      "$NIXOA_SYSTEM_ROOT/scripts/tui/action.sh" set-development-mode false
      ;;
    toggle)
      "$NIXOA_SYSTEM_ROOT/scripts/tui/action.sh" toggle-development-mode
      ;;
    --help|-h)
      printf 'Usage: nxcli host development-mode [status|on|off|toggle]\n'
      ;;
    *)
      nixoa_print_error "Unknown Development Mode action: $mode"
      return 1
      ;;
  esac
}

dispatch_host() {
  local subcommand="${1:-}"
  shift || true
  case "$subcommand" in
    show) host_show "$@" ;;
    edit)
      [ "$#" -eq 0 ] || {
        nixoa_print_error "host edit does not accept a target."
        return 1
      }
      exec "$(nixoa_default_editor)" "$NIXOA_SETTINGS_FILE" "$NIXOA_MENU_FILE"
      ;;
    development-mode) host_development_mode "$@" ;;
    help|--help|-h)
      printf 'Usage: nxcli host {show|edit|development-mode}\n'
      ;;
    add|list|select-vm)
      nixoa_print_error "nxcli host $subcommand was removed; this repository defines only nixoa."
      return 1
      ;;
    *)
      nixoa_print_error "Unknown host command: ${subcommand:-<missing>}"
      return 1
      ;;
  esac
}

commit_changes() {
  local message="${1:-}"
  [ "$#" -le 1 ] || {
    nixoa_print_error "commit accepts at most one message."
    return 1
  }
  nixoa_require_git_repo
  nixoa_cd_root
  nixoa_stage_changes
  if ! nixoa_has_staged_changes; then
    nixoa_print_success "No changes to commit."
    return
  fi
  nixoa_commit_changes "${message:-Record local NiXOA changes}"
}

show_diff() {
  local staged=0
  case "${1:-}" in
    "") ;;
    --json)
      show_diff_json
      return
      ;;
    --staged) staged=1 ;;
    --help|-h)
      printf 'Usage: nxcli diff [--json|--staged]\n'
      return
      ;;
    *)
      nixoa_print_error "Unknown diff option: $1"
      return 1
      ;;
  esac
  if [ "$staged" -eq 1 ]; then
    git -C "$NIXOA_SYSTEM_ROOT" diff --cached -- "${NIXOA_TRACKED_PATHS[@]}"
  else
    nixoa_print_change_summary
    git -C "$NIXOA_SYSTEM_ROOT" diff -- "${NIXOA_TRACKED_PATHS[@]}"
  fi
}

show_history() {
  [ "$#" -eq 0 ] || {
    nixoa_print_error "history accepts no arguments."
    return 1
  }
  git -C "$NIXOA_SYSTEM_ROOT" log --oneline --decorate --graph -10 -- "${NIXOA_TRACKED_PATHS[@]}"
}

run_apply_config() {
  local rebuild_action="switch" record_action="switch"
  local first_install=false rollback=false dry_run=0 ask=0 verbose=0 cores=""
  local current_head exit_code=0 sudo_bin
  local -a extra_args=() rebuild_cmd=() run_cmd=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --target|--hostname)
        nixoa_print_error "Target selection was removed; use the fixed .#nixoa target."
        return 1
        ;;
      --build)
        rebuild_action=build
        record_action=build
        shift
        ;;
      --boot)
        rebuild_action=boot
        record_action=boot
        shift
        ;;
      --dry-run)
        dry_run=1
        record_action=dry-run
        shift
        ;;
      --rollback)
        rollback=true
        record_action=rollback
        shift
        ;;
      --first-install)
        first_install=true
        shift
        ;;
      --ask)
        ask=1
        shift
        ;;
      --cores)
        [ "$#" -ge 2 ] || {
          nixoa_print_error "--cores requires a value."
          return 1
        }
        cores="$2"
        shift 2
        ;;
      --verbose)
        verbose=1
        shift
        ;;
      --help|-h)
        show_apply_help
        return
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
  current_head="$(git rev-parse HEAD 2>/dev/null || true)"

  if [ "$rollback" = true ]; then
    if [ "$ask" -eq 1 ] && ! nixoa_confirm "Roll back the current system generation"; then
      nixoa_print_warning "Rollback cancelled."
      return 1
    fi
    rebuild_cmd=(nixos-rebuild switch --rollback -L)
  elif [ "$first_install" = true ] && [ "$record_action" = switch ]; then
    nixoa_build_first_install_switch_command rebuild_cmd
    rebuild_cmd+=("${extra_args[@]}")
  else
    nixoa_build_nh_command rebuild_cmd "$rebuild_action" "$ask" "$cores" "$verbose"
    [ "$dry_run" -eq 0 ] || rebuild_cmd+=(--dry)
    if [ "${#extra_args[@]}" -gt 0 ]; then
      rebuild_cmd+=(-- "${extra_args[@]}")
    fi
  fi

  if [ "$rollback" = true ] || { [ "$first_install" = true ] && [ "$record_action" = switch ]; }; then
    if [ "$(id -u)" -ne 0 ]; then
      sudo_bin="$(nixoa_sudo_bin)" || return 1
      run_cmd=("$sudo_bin" "${rebuild_cmd[@]}")
    else
      run_cmd=("${rebuild_cmd[@]}")
    fi
  else
    run_cmd=(nixoa_run_nh "${rebuild_cmd[@]}")
  fi

  printf 'Running:'
  printf ' %q' "${run_cmd[@]}"
  printf '\n'

  if "${run_cmd[@]}"; then
    nixoa_write_apply_state success "$record_action" "$current_head" "$first_install" 0
  else
    exit_code="$?"
    nixoa_write_apply_state failed "$record_action" "$current_head" "$first_install" "$exit_code"
    return "$exit_code"
  fi
}

preview_update() {
  local temporary
  temporary="$(mktemp)"
  cp "$NIXOA_SYSTEM_ROOT/flake.lock" "$temporary"
  if [ "$#" -gt 0 ]; then
    nix flake update --output-lock-file "$temporary" "$@"
  else
    nix flake update --output-lock-file "$temporary"
  fi
  if git diff --no-index --quiet -- flake.lock "$temporary"; then
    nixoa_print_success "No lock-file changes found."
  else
    git diff --no-index -- flake.lock "$temporary" || true
  fi
  rm -f "$temporary"
}

update_input() {
  local input="${1:-}"
  shift || true
  local preview=0 ask=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --preview) preview=1; shift ;;
      --ask) ask=1; shift ;;
      --help|-h) show_update_help; return ;;
      --target|--hostname)
        nixoa_print_error "Target selection was removed; updates apply to the nixoa flake."
        return 1
        ;;
      *)
        nixoa_print_error "Unknown update option: $1"
        return 1
        ;;
    esac
  done
  nixoa_cd_root
  if [ "$ask" -eq 1 ] && ! nixoa_confirm "Update ${input:-all flake inputs}"; then
    nixoa_print_warning "Update cancelled."
    return 1
  fi
  if [ "$preview" -eq 1 ]; then
    if [ -n "$input" ]; then preview_update "$input"; else preview_update; fi
    return
  fi
  if [ -n "$input" ]; then
    nix flake update "$input"
  else
    nix flake update
  fi
  nixoa_print_success "Flake inputs updated."
  nixoa_print_cli_command "Next:" apply
  nixoa_print_cli_command "Safer path:" boot
}

dispatch_update() {
  local subcommand="${1:-}"
  shift || true
  case "$subcommand" in
    flake) update_input "" "$@" ;;
    xoa) update_input xen-orchestra-ce "$@" ;;
    help|--help|-h) show_update_help ;;
    *)
      nixoa_print_error "Unknown update command: ${subcommand:-<missing>}"
      return 1
      ;;
  esac
}

dispatch_xo() {
  case "${1:-}" in
    logs)
      [ "$#" -eq 1 ] || {
        nixoa_print_error "xo logs accepts no arguments."
        return 1
      }
      exec journalctl -u xo-server -u "$(nixoa_redis_service_name)" -e -f
      ;;
    help|--help|-h)
      printf 'Usage: nxcli xo logs\n'
      ;;
    *)
      nixoa_print_error "Unknown xo command: ${1:-<missing>}"
      return 1
      ;;
  esac
}

dispatch_generations() {
  case "${1:-}" in
    list)
      [ "$#" -eq 1 ] || {
        nixoa_print_error "generations list accepts no arguments."
        return 1
      }
      nixoa_run_as_root nix-env --list-generations -p /nix/var/nix/profiles/system
      ;;
    help|--help|-h)
      printf 'Usage: nxcli generations list\n'
      ;;
    *)
      nixoa_print_error "Unknown generations command: ${1:-<missing>}"
      return 1
      ;;
  esac
}

main() {
  local command="${1:-help}"
  shift || true
  case "$command" in
    help|--help|-h) show_help ;;
    version) printf 'nxcli %s\n' "$NXCLI_VERSION" ;;
    status) show_status "$@" ;;
    apply) run_apply_config "$@" ;;
    boot) run_apply_config --boot "$@" ;;
    rollback) run_apply_config --rollback "$@" ;;
    commit) commit_changes "$@" ;;
    diff) show_diff "$@" ;;
    history) show_history "$@" ;;
    host) dispatch_host "$@" ;;
    update) dispatch_update "$@" ;;
    xo) dispatch_xo "$@" ;;
    generations) dispatch_generations "$@" ;;
    *)
      nixoa_print_error "Unknown command: $command"
      show_help >&2
      return 1
      ;;
  esac
}

main "$@"
