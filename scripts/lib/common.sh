#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

readonly NIXOA_SYSTEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly NIXOA_HOST_ROOT="$NIXOA_SYSTEM_ROOT/host"
readonly NIXOA_TEMPLATE_HOST="_template"
readonly NIXOA_AUTOMATION_DIR="_automation"
readonly NIXOA_VM_ALIAS_NAME="vm"
readonly NIXOA_DEFAULT_HOSTNAME="nixo-ce"
readonly NIXOA_DEFAULT_USERNAME="nixoa"
readonly NIXOA_DEFAULT_TIMEZONE="Europe/Paris"
readonly NIXOA_DEFAULT_GIT_NAME="NiXOA Admin"
readonly NIXOA_DEFAULT_GIT_EMAIL="nixoa@nixoa"
readonly -a NIXOA_TRACKED_PATHS=(
  AGENTS.md
  CHANGELOG.md
  README.md
  config.nixoa.toml
  docs
  flake.lock
  flake.nix
  host
  lib
  modules
  nixoa-cli.sh
  pkgs
  scripts
)

nixoa_system_root() {
  printf '%s\n' "$NIXOA_SYSTEM_ROOT"
}

nixoa_state_dir() {
  local default_state_home

  default_state_home="${XDG_STATE_HOME:-${HOME:-$NIXOA_SYSTEM_ROOT}/.local/state}"
  printf '%s\n' "${NIXOA_STATE_DIR:-$default_state_home/nixoa}"
}

nixoa_shared_state_dir() {
  printf '%s\n' "${NIXOA_SHARED_STATE_DIR:-/var/lib/nixoa}"
}

nixoa_apply_state_file() {
  printf '%s\n' "${NIXOA_STATUS_FILE:-$(nixoa_shared_state_dir)/apply-state.env}"
}

nixoa_legacy_apply_state_file() {
  printf '%s\n' "$(nixoa_state_dir)/apply-state.env"
}

nixoa_rebuild_queue_file() {
  printf '%s\n' "${NIXOA_REBUILD_QUEUE_FILE:-$(nixoa_shared_state_dir)/rebuild-on-boot.env}"
}

nixoa_vm_alias_file() {
  printf '%s\n' "$NIXOA_HOST_ROOT/$NIXOA_AUTOMATION_DIR/default.nix"
}

nixoa_existing_host_dirs() {
  [ -d "$NIXOA_HOST_ROOT" ] || return 0
  find "$NIXOA_HOST_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name '_*' | sort
}

nixoa_read_string_file() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;.*$/\\1/p" "$file" | tail -n 1
}

nixoa_vm_alias_host() {
  local alias_host

  alias_host="$(nixoa_read_string_file vmHost "$(nixoa_vm_alias_file)" || true)"
  [ -n "$alias_host" ] || return 1
  printf '%s\n' "$alias_host"
}

nixoa_vm_alias_output_name() {
  local alias_host

  alias_host="$(nixoa_vm_alias_host || true)"
  [ -n "$alias_host" ] || return 1
  printf '%s-vm\n' "$alias_host"
}

nixoa_resolve_host_dir() {
  local host_ref="${1:-}"
  local dir=""
  local current_hostname=""
  local alias_host=""
  local alias_output=""

  if [ -n "$host_ref" ] && [ -d "$host_ref" ]; then
    printf '%s\n' "$host_ref"
    return 0
  fi

  alias_host="$(nixoa_vm_alias_host || true)"
  alias_output="$(nixoa_vm_alias_output_name || true)"

  if [ -n "$host_ref" ] && [ "$host_ref" = "$NIXOA_VM_ALIAS_NAME" ] && [ -n "$alias_host" ]; then
    host_ref="$alias_host"
  fi

  if [ -n "$host_ref" ] && [ -n "$alias_output" ] && [ "$host_ref" = "$alias_output" ] && [ -n "$alias_host" ]; then
    host_ref="$alias_host"
  fi

  if [ -n "$host_ref" ] && [[ "$host_ref" == *-vm ]] && [ -d "$NIXOA_HOST_ROOT/${host_ref%-vm}" ]; then
    printf '%s\n' "$NIXOA_HOST_ROOT/${host_ref%-vm}"
    return 0
  fi

  if [ -n "$host_ref" ] && [ -d "$NIXOA_HOST_ROOT/$host_ref" ]; then
    printf '%s\n' "$NIXOA_HOST_ROOT/$host_ref"
    return 0
  fi

  if [ -n "$host_ref" ]; then
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      current_hostname="$(nixoa_read_string_file hostname "$dir/_ctx/menu.nix" || true)"
      if [ -z "$current_hostname" ]; then
        current_hostname="$(nixoa_read_string_file hostname "$dir/_ctx/settings.nix" || true)"
      fi
      if [ "$current_hostname" = "$host_ref" ]; then
        printf '%s\n' "$dir"
        return 0
      fi
    done < <(nixoa_existing_host_dirs)
  fi

  return 1
}

nixoa_default_host_dir() {
  local host_dir=""
  local runtime_hostname=""
  local -a host_dirs=()

  if [ -n "${NIXOA_HOSTNAME:-}" ]; then
    nixoa_resolve_host_dir "$NIXOA_HOSTNAME" && return 0
  fi

  runtime_hostname="$(hostname -s 2>/dev/null || true)"
  if [ -n "$runtime_hostname" ]; then
    nixoa_resolve_host_dir "$runtime_hostname" && return 0
  fi

  if [ -d "$NIXOA_HOST_ROOT/$NIXOA_DEFAULT_HOSTNAME" ]; then
    printf '%s\n' "$NIXOA_HOST_ROOT/$NIXOA_DEFAULT_HOSTNAME"
    return 0
  fi

  mapfile -t host_dirs < <(nixoa_existing_host_dirs)
  if [ "${#host_dirs[@]}" -eq 1 ]; then
    printf '%s\n' "${host_dirs[0]}"
    return 0
  fi

  return 1
}

nixoa_host_settings_file() {
  local host_dir

  host_dir="$(nixoa_resolve_host_dir "${1:-}" 2>/dev/null || nixoa_default_host_dir)"
  printf '%s/_ctx/settings.nix\n' "$host_dir"
}

nixoa_host_menu_file() {
  local host_dir

  host_dir="$(nixoa_resolve_host_dir "${1:-}" 2>/dev/null || nixoa_default_host_dir)"
  printf '%s/_ctx/menu.nix\n' "$host_dir"
}

nixoa_host_relpath() {
  local host_dir

  host_dir="$(nixoa_resolve_host_dir "${1:-}" 2>/dev/null || nixoa_default_host_dir)"
  printf '%s\n' "${host_dir#"$NIXOA_SYSTEM_ROOT/"}"
}

nixoa_config_string() {
  local key="$1"
  local host_ref="${2:-}"
  local file
  local value

  for file in \
    "$(nixoa_host_menu_file "$host_ref")" \
    "$(nixoa_host_settings_file "$host_ref")"
  do
    [ -f "$file" ] || continue
    value="$(nixoa_read_string_file "$key" "$file" || true)"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

nixoa_default_hostname() {
  if [ -n "${NIXOA_HOSTNAME:-}" ]; then
    printf '%s\n' "$NIXOA_HOSTNAME"
    return 0
  fi

  nixoa_config_string hostname || printf '%s\n' "$NIXOA_DEFAULT_HOSTNAME"
}

nixoa_default_target() {
  local runtime_hostname=""
  local alias_output=""
  local host_dir=""

  if [ -n "${NIXOA_HOSTNAME:-}" ]; then
    nixoa_host_output_name "$NIXOA_HOSTNAME"
    return 0
  fi

  runtime_hostname="$(hostname -s 2>/dev/null || true)"
  alias_output="$(nixoa_vm_alias_output_name || true)"

  if [ -n "$runtime_hostname" ] && [ -n "$alias_output" ] && [ "$runtime_hostname" = "$alias_output" ]; then
    printf '%s\n' "$NIXOA_VM_ALIAS_NAME"
    return 0
  fi

  if [ -n "$runtime_hostname" ] && nixoa_resolve_host_dir "$runtime_hostname" >/dev/null 2>&1; then
    printf '%s\n' "$runtime_hostname"
    return 0
  fi

  host_dir="$(nixoa_default_host_dir 2>/dev/null || true)"
  if [ -n "$host_dir" ]; then
    printf '%s\n' "$(basename "$host_dir")"
    return 0
  fi

  printf '%s\n' "$NIXOA_DEFAULT_HOSTNAME"
}

nixoa_git_user_name() {
  nixoa_config_string gitName || printf '%s\n' "$NIXOA_DEFAULT_GIT_NAME"
}

nixoa_git_user_email() {
  nixoa_config_string gitEmail || printf '%s\n' "$NIXOA_DEFAULT_GIT_EMAIL"
}

nixoa_host_output_name() {
  local host_ref="${1:-}"
  local alias_output=""

  if [ -z "$host_ref" ]; then
    host_ref="$(nixoa_default_target)"
  fi

  if [ "$host_ref" = "$NIXOA_VM_ALIAS_NAME" ]; then
    printf '%s\n' "$NIXOA_VM_ALIAS_NAME"
    return 0
  fi

  alias_output="$(nixoa_vm_alias_output_name || true)"
  if [ -n "$alias_output" ] && [ "$host_ref" = "$alias_output" ]; then
    printf '%s\n' "$NIXOA_VM_ALIAS_NAME"
    return 0
  fi

  printf '%s\n' "$host_ref"
}

nixoa_host_flake_ref() {
  local hostname="${1:-}"
  printf '.#nixosConfigurations.%s\n' "$(nixoa_host_output_name "$hostname")"
}

nixoa_cd_root() {
  cd "$NIXOA_SYSTEM_ROOT"
}

nixoa_require_git_repo() {
  if [ ! -d "$NIXOA_SYSTEM_ROOT/.git" ]; then
    echo "Error: $NIXOA_SYSTEM_ROOT is not a git repository." >&2
    exit 1
  fi
}

nixoa_sudo_bin() {
  if [ -x /run/wrappers/bin/sudo ]; then
    printf '%s\n' /run/wrappers/bin/sudo
    return 0
  fi

  command -v sudo 2>/dev/null || return 1
}

nixoa_run_as_root() {
  local sudo_bin

  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi

  sudo_bin="$(nixoa_sudo_bin)" || {
    echo "Error: root access is required for this step, but sudo is not available." >&2
    return 1
  }

  "$sudo_bin" "$@"
}

nixoa_run_nh() {
  if command -v nh >/dev/null 2>&1; then
    nh "$@"
    return $?
  fi

  nix shell nixpkgs#nh -c nh "$@"
}

nixoa_status_porcelain() {
  git -C "$NIXOA_SYSTEM_ROOT" status --short -- "${NIXOA_TRACKED_PATHS[@]}"
}

nixoa_has_changes() {
  [ -n "$(nixoa_status_porcelain)" ]
}

nixoa_stage_changes() {
  git -C "$NIXOA_SYSTEM_ROOT" add -A -- "${NIXOA_TRACKED_PATHS[@]}"
}

nixoa_has_staged_changes() {
  ! git -C "$NIXOA_SYSTEM_ROOT" diff --cached --quiet -- "${NIXOA_TRACKED_PATHS[@]}"
}

nixoa_print_change_summary() {
  echo "=== Configuration Changes ==="
  git -C "$NIXOA_SYSTEM_ROOT" diff HEAD --stat -- "${NIXOA_TRACKED_PATHS[@]}" 2>/dev/null || true

  if nixoa_has_changes; then
    echo ""
    nixoa_status_porcelain
  fi

  echo ""
}

nixoa_generate_commit_body() {
  local updated=()
  local added=()
  local removed=()
  local renamed=()
  local emitted=0
  local status=""
  local first=""
  local second=""

  while IFS=$'\t' read -r status first second; do
    [ -n "$status" ] || continue

    case "$status" in
      A*)
        added+=("$first")
        ;;
      D*)
        removed+=("$first")
        ;;
      R*)
        renamed+=("$first -> $second")
        ;;
      *)
        updated+=("$first")
        ;;
    esac
  done < <(git -C "$NIXOA_SYSTEM_ROOT" diff --cached --name-status --find-renames -- "${NIXOA_TRACKED_PATHS[@]}")

  if [ "${#updated[@]}" -gt 0 ]; then
    echo "Updated:"
    printf -- '- %s\n' "${updated[@]}"
    emitted=1
  fi

  if [ "${#added[@]}" -gt 0 ]; then
    [ "$emitted" -eq 1 ] && echo ""
    echo "Added:"
    printf -- '- %s\n' "${added[@]}"
    emitted=1
  fi

  if [ "${#removed[@]}" -gt 0 ]; then
    [ "$emitted" -eq 1 ] && echo ""
    echo "Removed:"
    printf -- '- %s\n' "${removed[@]}"
    emitted=1
  fi

  if [ "${#renamed[@]}" -gt 0 ]; then
    [ "$emitted" -eq 1 ] && echo ""
    echo "Renamed:"
    printf -- '- %s\n' "${renamed[@]}"
  fi
}

nixoa_commit_changes() {
  local commit_message="${1:-}"
  local subject="Record local NiXOA changes"
  local body=""
  local git_name=""
  local git_email=""
  local -a git_commit_cmd=()

  if [ -z "${commit_message//[[:space:]]/}" ] && [ -t 0 ]; then
    read -r -p "Commit message [auto]: " commit_message
  fi

  if [ -n "${commit_message//[[:space:]]/}" ]; then
    git_name="$(nixoa_git_user_name)"
    git_email="$(nixoa_git_user_email)"
    git_commit_cmd=(
      git
      -C "$NIXOA_SYSTEM_ROOT"
      -c "user.name=$git_name"
      -c "user.email=$git_email"
      commit
    )
    "${git_commit_cmd[@]}" -m "$commit_message"
    return 0
  fi

  body="$(nixoa_generate_commit_body)"
  git_name="$(nixoa_git_user_name)"
  git_email="$(nixoa_git_user_email)"
  git_commit_cmd=(
    git
    -C "$NIXOA_SYSTEM_ROOT"
    -c "user.name=$git_name"
    -c "user.email=$git_email"
    commit
  )
  if [ -n "$body" ]; then
    "${git_commit_cmd[@]}" -m "$subject" -m "$body"
  else
    "${git_commit_cmd[@]}" -m "$subject"
  fi
}

nixoa_write_apply_state() {
  local result="$1"
  local action="$2"
  local hostname="$3"
  local head="$4"
  local first_install="$5"
  local exit_code="$6"
  local state_file
  local state_dir
  local temp_file
  local first_install_bool="false"

  case "$first_install" in
    1|true|TRUE|yes|on)
      first_install_bool="true"
      ;;
  esac

  state_file="$(nixoa_apply_state_file)"
  state_dir="$(dirname "$state_file")"
  temp_file="$(mktemp)"

  {
    printf 'last_apply_result=%s\n' "$result"
    printf 'last_apply_action=%s\n' "$action"
    printf 'last_apply_hostname=%s\n' "$hostname"
    printf 'last_apply_head=%s\n' "$head"
    printf 'last_apply_first_install=%s\n' "$first_install_bool"
    printf 'last_apply_exit_code=%s\n' "$exit_code"
    printf 'last_apply_timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$temp_file"

  if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0755 "$state_dir"
    install -m 0644 "$temp_file" "$state_file"
  else
    nixoa_run_as_root install -d -m 0755 "$state_dir"
    nixoa_run_as_root install -m 0644 "$temp_file" "$state_file"
  fi

  rm -f "$temp_file"
}

nixoa_schedule_rebuild_on_boot() {
  local repo_root="$1"
  local target="$2"
  local queue_file
  local queue_dir

  target="$(nixoa_host_output_name "$target")"
  queue_file="$(nixoa_rebuild_queue_file)"
  queue_dir="$(dirname "$queue_file")"

  if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0755 "$queue_dir"
    {
      printf 'repo_root=%q\n' "$repo_root"
      printf 'target=%q\n' "$target"
      printf 'hostname=%q\n' "$target"
      printf 'scheduled_at=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$queue_file"
    return 0
  fi

  nixoa_run_as_root install -d -m 0755 "$queue_dir"
  {
    printf 'repo_root=%q\n' "$repo_root"
    printf 'target=%q\n' "$target"
    printf 'hostname=%q\n' "$target"
    printf 'scheduled_at=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } | nixoa_run_as_root tee "$queue_file" >/dev/null
}
