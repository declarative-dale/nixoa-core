#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

readonly NIXOA_SYSTEM_ROOT="${NIXOA_SYSTEM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
readonly NIXOA_TARGET="nixoa"
readonly NIXOA_HOST_ROOT="$NIXOA_SYSTEM_ROOT/host"
readonly NIXOA_SETTINGS_FILE="$NIXOA_HOST_ROOT/settings.nix"
readonly NIXOA_MENU_FILE="$NIXOA_HOST_ROOT/menu.nix"
readonly NIXOA_HARDWARE_FILE="$NIXOA_HOST_ROOT/hardware-configuration.nix"
readonly NIXOA_DEFAULT_HOSTNAME="nixoa"
readonly NIXOA_DEFAULT_USERNAME="nixoa"
# Used by scripts that source this shared library.
# shellcheck disable=SC2034
readonly NIXOA_DEFAULT_TIMEZONE="America/Chicago"
readonly NIXOA_DEFAULT_GIT_NAME="NiXOA Admin"
readonly NIXOA_DEFAULT_GIT_EMAIL="nixoa@nixoa"
readonly NIXOA_DETERMINATE_SUBSTITUTER="https://install.determinate.systems"
readonly NIXOA_CORE_SUBSTITUTER="https://nixoa.cachix.org"
readonly NIXOA_XO_SUBSTITUTER="https://xen-orchestra-ce.cachix.org"
readonly NIXOA_LIBVHDI_SUBSTITUTER="https://libvhdi-nixpkg.cachix.org"
readonly NIXOA_DETERMINATE_PUBLIC_KEY="cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
readonly NIXOA_CORE_PUBLIC_KEY="nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
readonly NIXOA_XO_PUBLIC_KEY="xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
readonly NIXOA_LIBVHDI_PUBLIC_KEY="libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4="
readonly -a NIXOA_TRACKED_PATHS=(
  AGENTS.md
  CHANGELOG.md
  README.md
  docs
  flake.lock
  flake.nix
  host
  installer
  modules
  packer
  pkgs
  scripts
  tests
)

nixoa_print_error() {
  printf 'error: %s\n' "$1" >&2
}

nixoa_print_warning() {
  printf 'warn: %s\n' "$1" >&2
}

nixoa_print_info() {
  printf 'info: %s\n' "$1"
}

nixoa_print_success() {
  printf 'ok: %s\n' "$1"
}

nixoa_cli_command() {
  if command -v nxcli >/dev/null 2>&1; then
    printf 'nxcli\n'
  else
    printf '%s/scripts/nxcli.sh\n' "$NIXOA_SYSTEM_ROOT"
  fi
}

nixoa_print_cli_command() {
  local prefix="$1"
  local command
  shift
  command="$(nixoa_cli_command)"
  printf '%s %q' "$prefix" "$command"
  printf ' %q' "$@"
  printf '\n'
}

nixoa_print_shell_command() {
  local prefix="$1"
  shift
  printf '%s' "$prefix"
  printf ' %q' "$@"
  printf '\n'
}

nixoa_nix_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

nixoa_system_root() {
  printf '%s\n' "$NIXOA_SYSTEM_ROOT"
}

nixoa_host_settings_file() {
  printf '%s\n' "$NIXOA_SETTINGS_FILE"
}

nixoa_host_menu_file() {
  printf '%s\n' "$NIXOA_MENU_FILE"
}

nixoa_host_hardware_file() {
  printf '%s\n' "$NIXOA_HARDWARE_FILE"
}

nixoa_host_relpath() {
  printf 'host\n'
}

nixoa_read_string_file() {
  local key="$1"
  local file="$2"
  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*(${key}|[A-Za-z0-9_.-]+\\.${key})[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;.*$/\\2/p" "$file" | tail -n 1
}

nixoa_config_string() {
  local key="$1"
  local file value
  for file in "$NIXOA_MENU_FILE" "$NIXOA_SETTINGS_FILE"; do
    value="$(nixoa_read_string_file "$key" "$file" || true)"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

nixoa_default_hostname() {
  nixoa_config_string hostName || printf '%s\n' "$NIXOA_DEFAULT_HOSTNAME"
}

nixoa_default_target() {
  printf '%s\n' "$NIXOA_TARGET"
}

nixoa_host_output_name() {
  case "${1:-$NIXOA_TARGET}" in
    "$NIXOA_TARGET") printf '%s\n' "$NIXOA_TARGET" ;;
    *) return 1 ;;
  esac
}

nixoa_resolve_target_output() {
  nixoa_host_output_name "${1:-$NIXOA_TARGET}"
}

nixoa_resolve_target_host() {
  nixoa_host_output_name "${1:-$NIXOA_TARGET}"
}

nixoa_require_target_output() {
  local requested="${1:-$NIXOA_TARGET}"
  if [ "$requested" != "$NIXOA_TARGET" ]; then
    nixoa_print_error "NiXOA has one fixed target: $NIXOA_TARGET."
    return 1
  fi
  printf '%s\n' "$NIXOA_TARGET"
}

nixoa_target_summary_line() {
  nixoa_require_target_output "${1:-}" >/dev/null
  printf 'target=nixoa host=nixoa host_dir=host\n'
}

nixoa_host_flake_ref() {
  printf 'path:%s#nixosConfigurations.nixoa\n' "$NIXOA_SYSTEM_ROOT"
}

nixoa_nixos_rebuild_flake_ref() {
  printf 'path:%s#nixoa\n' "$NIXOA_SYSTEM_ROOT"
}

nixoa_git_user_name() {
  nixoa_config_string gitName || printf '%s\n' "$NIXOA_DEFAULT_GIT_NAME"
}

nixoa_git_user_email() {
  nixoa_config_string gitEmail || printf '%s\n' "$NIXOA_DEFAULT_GIT_EMAIL"
}

nixoa_cd_root() {
  builtin cd "$NIXOA_SYSTEM_ROOT" || return
}

nixoa_require_git_repo() {
  if [ ! -d "$NIXOA_SYSTEM_ROOT/.git" ]; then
    nixoa_print_error "$NIXOA_SYSTEM_ROOT is not a git repository."
    return 1
  fi
}

nixoa_sudo_bin() {
  if [ -x /run/wrappers/bin/sudo ]; then
    printf '/run/wrappers/bin/sudo\n'
  else
    command -v sudo 2>/dev/null
  fi
}

nixoa_run_as_root() {
  local sudo_bin
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi
  sudo_bin="$(nixoa_sudo_bin)" || {
    nixoa_print_error "Root access is required, but sudo is unavailable."
    return 1
  }
  "$sudo_bin" "$@"
}

nixoa_user_exists() {
  [ -n "${1:-}" ] && [ "$1" != root ] && id -u "$1" >/dev/null 2>&1
}

nixoa_host_execution_user() {
  local repo_owner
  if nixoa_user_exists "${NIXOA_NH_USER:-}"; then
    printf '%s\n' "$NIXOA_NH_USER"
  elif nixoa_user_exists nixoa; then
    printf 'nixoa\n'
  elif nixoa_user_exists "${SUDO_USER:-}"; then
    printf '%s\n' "$SUDO_USER"
  else
    repo_owner="$(stat -c %U "$NIXOA_SYSTEM_ROOT" 2>/dev/null || true)"
    nixoa_user_exists "$repo_owner" && printf '%s\n' "$repo_owner"
  fi
}

nixoa_run_nh() {
  local operator sudo_bin
  command -v nh >/dev/null 2>&1 || {
    nixoa_print_error "nh is required for this action."
    return 127
  }
  if [ "$(id -u)" -eq 0 ]; then
    operator="$(nixoa_host_execution_user || true)"
    if [ -n "$operator" ]; then
      sudo_bin="$(nixoa_sudo_bin)" || return 1
      "$sudo_bin" -H -u "$operator" nh "$@"
      return $?
    fi
  fi
  nh "$@"
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
  printf '=== Configuration Changes ===\n'
  git -C "$NIXOA_SYSTEM_ROOT" diff HEAD --stat -- "${NIXOA_TRACKED_PATHS[@]}" 2>/dev/null || true
  nixoa_status_porcelain || true
}

nixoa_commit_changes() {
  local message="${1:-Record local NiXOA changes}"
  local git_name git_email
  git_name="$(nixoa_git_user_name)"
  git_email="$(nixoa_git_user_email)"
  git -C "$NIXOA_SYSTEM_ROOT" \
    -c "user.name=$git_name" \
    -c "user.email=$git_email" \
    commit -m "$message"
}

nixoa_state_dir() {
  local base="${XDG_STATE_HOME:-${HOME:-$NIXOA_SYSTEM_ROOT}/.local/state}"
  printf '%s\n' "${NIXOA_STATE_DIR:-$base/nixoa}"
}

nixoa_shared_state_dir() {
  printf '%s\n' "${NIXOA_SHARED_STATE_DIR:-/var/lib/nixoa}"
}

nixoa_apply_state_file() {
  printf '%s\n' "${NIXOA_STATUS_FILE:-$(nixoa_shared_state_dir)/apply-state.env}"
}

nixoa_legacy_apply_state_file() {
  printf '%s/apply-state.env\n' "$(nixoa_state_dir)"
}

nixoa_rebuild_queue_file() {
  printf '%s\n' "${NIXOA_REBUILD_QUEUE_FILE:-$(nixoa_shared_state_dir)/rebuild-on-boot.env}"
}

nixoa_install_state_file() {
  local source="$1"
  local destination="$2"
  local directory
  directory="$(dirname "$destination")"
  if [ "$(id -u)" -eq 0 ] || { [ -d "$directory" ] && [ -w "$directory" ]; }; then
    mkdir -p "$directory"
    install -m 0644 "$source" "$destination"
  else
    nixoa_run_as_root install -d -m 0755 "$directory"
    nixoa_run_as_root install -m 0644 "$source" "$destination"
  fi
}

nixoa_write_apply_state() {
  local result="$1" action="$2" head="$3" first_install="$4" exit_code="$5"
  local temporary
  temporary="$(mktemp)"
  {
    printf 'last_apply_result=%s\n' "$result"
    printf 'last_apply_action=%s\n' "$action"
    printf 'last_apply_hostname=nixoa\n'
    printf 'last_apply_head=%s\n' "$head"
    printf 'last_apply_first_install=%s\n' "$first_install"
    printf 'last_apply_exit_code=%s\n' "$exit_code"
    printf 'last_apply_timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$temporary"
  nixoa_install_state_file "$temporary" "$(nixoa_apply_state_file)"
  rm -f "$temporary"
}

nixoa_schedule_rebuild_on_boot() {
  local repo_root="${1:-$NIXOA_SYSTEM_ROOT}"
  local queue temporary
  queue="$(nixoa_rebuild_queue_file)"
  temporary="$(mktemp)"
  {
    printf 'repo_root=%q\n' "$repo_root"
    printf 'scheduled_at=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$temporary"
  nixoa_install_state_file "$temporary" "$queue"
  rm -f "$temporary"
}

nixoa_validate_hostname() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || {
    nixoa_print_error "Invalid hostname '$1'."
    return 1
  }
}

nixoa_validate_username() {
  [ "$1" = "$NIXOA_DEFAULT_USERNAME" ] || {
    nixoa_print_error "The appliance operator is fixed to '$NIXOA_DEFAULT_USERNAME'."
    return 1
  }
}

nixoa_default_editor() {
  printf '%s\n' "${VISUAL:-${EDITOR:-vi}}"
}

nixoa_prompt_with_default() {
  local prompt="$1" default="$2" reply=""
  if [ ! -t 0 ]; then
    printf '%s\n' "$default"
    return
  fi
  read -r -p "$prompt [$default]: " reply
  printf '%s\n' "${reply:-$default}"
}

nixoa_confirm() {
  local reply
  [ -t 0 ] || return 1
  read -r -p "$1 [y/N]: " reply
  [[ "$reply" =~ ^([yY]|yes|YES)$ ]]
}

nixoa_require_clean_repo() {
  nixoa_require_git_repo
  if nixoa_has_changes; then
    nixoa_print_error "Tracked NiXOA files have uncommitted changes."
    nixoa_status_porcelain >&2 || true
    return 1
  fi
}

nixoa_service_exists() {
  local state
  state="$(systemctl show "$1" -p LoadState --value 2>/dev/null || true)"
  [ -n "$state" ] && [ "$state" != not-found ]
}

nixoa_service_state() {
  if ! nixoa_service_exists "$1"; then
    printf 'unavailable\n'
  elif systemctl is-active "$1" >/dev/null 2>&1; then
    printf 'active\n'
  else
    printf 'inactive\n'
  fi
}

nixoa_redis_service_name() {
  local unit
  for unit in redis-xo.service valkey-xo.service; do
    if nixoa_service_exists "$unit"; then
      printf '%s\n' "$unit"
      return
    fi
  done
  printf 'redis-xo.service\n'
}

nixoa_render_status() {
  local redis dirty_count=0
  redis="$(nixoa_redis_service_name)"
  if nixoa_require_git_repo >/dev/null 2>&1; then
    dirty_count="$(nixoa_status_porcelain | wc -l | tr -d ' ')"
  fi
  printf 'Repo root: %s\n' "$NIXOA_SYSTEM_ROOT"
  printf 'Target: nixoa\n'
  printf 'xo-server.service: %s\n' "$(nixoa_service_state xo-server.service)"
  printf '%s: %s\n' "$redis" "$(nixoa_service_state "$redis")"
  if [ "$dirty_count" -eq 0 ]; then
    printf 'Git state: clean\n'
  else
    printf 'Git state: dirty (%s tracked path changes)\n' "$dirty_count"
  fi
}

nixoa_append_first_install_nix_options() {
  local -n command_ref="$1"
  command_ref+=(
    --option extra-experimental-features "nix-command flakes"
    --option extra-substituters "$NIXOA_DETERMINATE_SUBSTITUTER $NIXOA_CORE_SUBSTITUTER $NIXOA_XO_SUBSTITUTER $NIXOA_LIBVHDI_SUBSTITUTER"
    --option extra-trusted-public-keys "$NIXOA_DETERMINATE_PUBLIC_KEY $NIXOA_CORE_PUBLIC_KEY $NIXOA_XO_PUBLIC_KEY $NIXOA_LIBVHDI_PUBLIC_KEY"
  )
}

nixoa_build_first_install_switch_command() {
  # The caller passes the name of an array to populate.
  # shellcheck disable=SC2178
  local -n command_ref="$1"
  command_ref=(
    nixos-rebuild switch
    --flake "$(nixoa_nixos_rebuild_flake_ref)"
    -L
  )
  nixoa_append_first_install_nix_options "$1"
}

nixoa_run_first_install_flake_check() {
  local -a command=(
    nix flake check
    --no-write-lock-file
    "path:$NIXOA_SYSTEM_ROOT"
  )
  nixoa_append_first_install_nix_options command
  "${command[@]}"
}

nixoa_print_first_switch_commands() {
  local -a command
  nixoa_build_first_install_switch_command command
  nixoa_print_cli_command "Repo helper:" apply --first-install
  nixoa_print_shell_command "nixos-rebuild:" "${command[@]}"
}

nixoa_build_nh_command() {
  # The caller passes the name of an array to populate.
  # shellcheck disable=SC2178
  local -n command_ref="$1"
  local action="$2" ask="$3" cores="$4" verbose="$5"
  shift 5
  command_ref=(
    os "$action"
    "$(nixoa_host_flake_ref)"
    -L
  )
  if [ -n "$(nixoa_sudo_bin || true)" ]; then
    command_ref+=(--elevation-strategy "$(nixoa_sudo_bin)")
  fi
  [ "$ask" -eq 0 ] || command_ref+=(--ask)
  [ -z "$cores" ] || command_ref+=(--cores "$cores")
  [ "$verbose" -eq 0 ] || command_ref+=(--verbose)
  command_ref+=("$@")
}

nixoa_write_host_settings() {
  local settings_file="$1" repo_dir="$2" timezone="$3" state_version="$4"
  local git_name="$5" git_email="$6" keys_name="$7"
  local -n keys_ref="$keys_name"
  local key
  {
    printf '%s\n' '# SPDX-License-Identifier: Apache-2.0'
    printf '%s\n' '# Generated by bootstrap; edit this file for appliance policy.'
    printf '%s\n' '{lib, ...}: {'
    printf '  networking.hostName = "nixoa";\n'
    printf '  time.timeZone = %s;\n' "$(nixoa_nix_quote "$timezone")"
    printf '  system.stateVersion = %s;\n\n' "$(nixoa_nix_quote "$state_version")"
    printf '  boot.loader.systemd-boot.enable = true;\n'
    printf '  boot.loader.efi.canTouchEfiVariables = true;\n'
    printf '  networking.firewall.allowedTCPPorts = [80 443];\n\n'
    printf '  nixoa.operator = {\n'
    printf '    repoDir = %s;\n' "$(nixoa_nix_quote "$repo_dir")"
    printf '    gitName = %s;\n' "$(nixoa_nix_quote "$git_name")"
    printf '    gitEmail = %s;\n' "$(nixoa_nix_quote "$git_email")"
    printf '    sshKeys = lib.mkDefault [\n'
    for key in "${keys_ref[@]}"; do
      printf '      %s\n' "$(nixoa_nix_quote "$key")"
    done
    printf '    ];\n'
    printf '    enableExtras = lib.mkDefault false;\n'
    printf '    developmentMode = lib.mkDefault false;\n'
    printf '    menuAutoStart = false;\n'
    printf '    sudoNoPassword = true;\n'
    printf '    systemPackages = [];\n'
    printf '    userPackages = [];\n'
    printf '  };\n\n'
    printf '  nixoa.xo = {\n'
    printf '    enable = true;\n'
    printf '    httpHost = "0.0.0.0";\n'
    printf '    tls = { enable = true; autoCert = true; };\n'
    printf '    storage = {\n'
    printf '      enableNFS = true;\n'
    printf '      enableCIFS = true;\n'
    printf '      enableVHD = true;\n'
    printf '      mountsDir = "/var/lib/xo/mounts";\n'
    printf '    };\n'
    printf '  };\n'
    printf '}\n'
  } > "$settings_file"
}
