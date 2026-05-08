#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Canonical NiXOA operator CLI

set -euo pipefail

readonly NXCLI_VERSION="4.1.0"

resolve_repo_root() {
  local candidate=""
  local search_dir=""
  local script_dir=""

  if [ -n "${NIXOA_SYSTEM_ROOT:-}" ] && [ -f "${NIXOA_SYSTEM_ROOT}/scripts/lib/common.sh" ]; then
    printf '%s\n' "$NIXOA_SYSTEM_ROOT"
    return 0
  fi

  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    candidate="$(cd "$script_dir/.." && pwd)"
    if [ -f "$candidate/scripts/lib/common.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    if [ -f "$git_root/scripts/lib/common.sh" ]; then
      printf '%s\n' "$git_root"
      return 0
    fi
  fi

  search_dir="${PWD:-}"
  while [ -n "$search_dir" ] && [ "$search_dir" != "/" ]; do
    if [ -f "$search_dir/scripts/lib/common.sh" ]; then
      printf '%s\n' "$search_dir"
      return 0
    fi
    search_dir="$(dirname "$search_dir")"
  done

  if [ -n "${SUDO_USER:-}" ]; then
    candidate="$(getent passwd "$SUDO_USER" | cut -d: -f6)/nixoa"
    if [ -f "$candidate/scripts/lib/common.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in "${HOME:-}/nixoa" "${HOME:-}/projects/nixoa"; do
    if [ -f "$candidate/scripts/lib/common.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'error: could not find a NiXOA checkout. Run from the repo root or set NIXOA_SYSTEM_ROOT.\n' >&2
  exit 1
}

REPO_ROOT="$(resolve_repo_root)"
export NIXOA_SYSTEM_ROOT="$REPO_ROOT"
. "$REPO_ROOT/scripts/lib/common.sh"

show_help() {
  cat <<'EOF'
Usage:
  nxcli help
  nxcli version
  nxcli status [--json]
  nxcli apply [--target <hostname|vm>] [--build|--dry-run|--first-install] [--ask] [--cores N] [--verbose] [-- ...]
  nxcli boot [--target <hostname|vm>] [--ask] [--cores N] [--verbose] [-- ...]
  nxcli rollback [--target <hostname|vm>]
  nxcli commit [commit message]
  nxcli diff [--json]
  nxcli history
  nxcli host add [hostname] [--profile physical|vm] [--copy-hardware|--skip-hardware-copy] [--set-vm-alias|--no-set-vm-alias]
  nxcli host list [--json]
  nxcli host show [hostname] [--json]
  nxcli host select-vm <hostname>
  nxcli host edit [hostname]
  nxcli update flake [--preview] [--target <hostname|vm>] [--ask]
  nxcli update xoa [--preview] [--target <hostname|vm>] [--ask]
  nxcli xo logs
  nxcli generations list

Shared rebuild flags:
  --target <hostname|vm>   Canonical target selector. Accepts <hostname>, <hostname>-vm, or vm.
  --ask                    Ask nh for confirmation before mutating actions.
  --cores N                Pass through a core limit to nh.
  --verbose                Increase nh verbosity.

Notes:
  - host/_automation/default.nix is the stable vm selector behind --target vm.
  - nxcli is the supported operator interface for repository and system actions.
EOF
}

show_host_help() {
  cat <<'EOF'
Usage:
  nxcli host add [hostname] [options]
  nxcli host list [--json]
  nxcli host show [hostname] [--json]
  nxcli host select-vm <hostname>
  nxcli host edit [hostname]
EOF
}

show_host_add_help() {
  cat <<'EOF'
Usage: nxcli host add [hostname] [options]

Options:
  --profile NAME           Deployment profile: physical or vm. Defaults from virtualization detection.
  --copy-hardware          Copy /etc/nixos/hardware-configuration.nix into the new host tree. Default: yes.
  --skip-hardware-copy     Do not copy the local hardware profile. Use only when you intend to replace the generated placeholder manually.
  --set-vm-alias           Update host/_automation/default.nix to point vm at this host. Default: yes.
  --no-set-vm-alias        Leave the stable vm alias unchanged.
  --username NAME          Primary username. Default: nixoa.
  --git-name NAME          Git user.name override. Default: NiXOA Admin.
  --git-email EMAIL        Git user.email override. Default: nixoa@nixoa.
  --timezone ZONE          Time zone. Default: Europe/Paris.
  --state-version VER      State version. Default: 25.11.
  --ssh-key KEY            Add an SSH public key. Repeatable.
  --skip-check             Skip nix flake check after creating the host.
  --first-switch           Run the first switch after creating the host without prompting.
  --help                   Show this help text.
EOF
}

show_update_help() {
  cat <<'EOF'
Usage:
  nxcli update flake [--target <hostname|vm>] [--ask] [--preview]
  nxcli update xoa [--target <hostname|vm>] [--ask] [--preview]
EOF
}

show_apply_help() {
  cat <<'EOF'
Usage:
  nxcli apply [--target TARGET | --hostname TARGET] [--build | --dry-run] [--first-install] [--ask] [--cores N] [--verbose] [-- extra nh build args...]
  nxcli boot [--target TARGET | --hostname TARGET] [--ask] [--cores N] [--verbose] [-- extra nh build args...]
  nxcli rollback [--target TARGET | --hostname TARGET] [--ask]

Options:
  --target TARGET       Canonical target selector. Accepts <hostname>, <hostname>-vm, or vm.
  --hostname TARGET     Legacy alias for --target.
  --build               Build without switching.
  --dry-run             Preview the apply flow without mutating the system.
  --first-install       Add Determinate first-install cache flags for the initial switch.
  --ask                 Ask nh for confirmation before mutating actions.
  --cores N             Pass through the requested core count to nh.
  --verbose             Increase nh verbosity.
EOF
}

show_commit_help() {
  cat <<'EOF'
Usage:
  nxcli commit [commit message]

Commits tracked NiXOA repository changes. If no message is supplied and stdin is
interactive, nxcli prompts for one; an empty message auto-generates a structured
commit body from the staged files.
EOF
}

show_xo_help() {
  cat <<'EOF'
Usage:
  nxcli xo logs
EOF
}

show_generations_help() {
  cat <<'EOF'
Usage:
  nxcli generations list
EOF
}

show_version() {
  printf 'nxcli %s\n' "$NXCLI_VERSION"
  if command -v nixos-version >/dev/null 2>&1; then
    printf 'NixOS: %s\n' "$(nixos-version)"
  fi
}

nxcli_json_quote() {
  jq -Rn --arg value "$1" '$value'
}

nxcli_status_json() {
  local first=1
  local status=""
  local path=""

  printf '['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    status="${line:0:2}"
    path="${line:3}"

    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '\n    {"status": %s, "path": %s}' \
      "$(nxcli_json_quote "$status")" \
      "$(nxcli_json_quote "$path")"
    first=0
  done < <(nixoa_status_porcelain || true)

  if [ "$first" -eq 0 ]; then
    printf '\n  '
  fi
  printf ']'
}

show_status_json() {
  "$NIXOA_SYSTEM_ROOT/scripts/tui/state.sh" --json
}

show_diff_json() {
  printf '{\n  "changes": '
  nxcli_status_json
  printf '\n}\n'
}

host_list() {
  local json=0
  local selected_vm=""
  local host_dir=""
  local host_name=""
  local profile=""
  local first=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --help|-h)
        show_host_help
        exit 0
        ;;
      *)
        nixoa_print_error "Unknown host list option: $1"
        exit 1
        ;;
    esac
  done

  selected_vm="$(nixoa_vm_alias_host || true)"

  if [ "$json" -eq 1 ]; then
    printf '{\n  "hosts": ['
  fi

  while IFS= read -r host_dir; do
    [ -n "$host_dir" ] || continue
    host_name="$(basename "$host_dir")"
    profile="$(nixoa_config_string deploymentProfile "$host_name" || true)"
    if [ "$json" -eq 1 ]; then
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      printf '\n    {"name": %s, "profile": %s, "vmSelected": %s}' \
        "$(nxcli_json_quote "$host_name")" \
        "$(nxcli_json_quote "${profile:-unknown}")" \
        "$( [ "$host_name" = "$selected_vm" ] && printf true || printf false )"
      first=0
      continue
    fi

    if [ "$host_name" = "$selected_vm" ]; then
      printf '%s\tprofile=%s\tvm=selected\n' "$host_name" "${profile:-unknown}"
    else
      printf '%s\tprofile=%s\n' "$host_name" "${profile:-unknown}"
    fi
  done < <(nixoa_existing_host_dirs)

  if [ "$json" -eq 1 ]; then
    if [ "$first" -eq 0 ]; then
      printf '\n  '
    fi
    printf ']\n}\n'
  fi
}

host_show() {
  local target=""
  local json=0
  local resolved_target=""
  local host_name=""
  local host_dir=""
  local settings_file=""
  local menu_file=""
  local selected_vm=""
  local username=""
  local timezone=""
  local profile=""
  local repo_dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --help|-h)
        show_host_help
        exit 0
        ;;
      --*)
        nixoa_print_error "Unknown host show option: $1"
        exit 1
        ;;
      *)
        if [ -n "$target" ]; then
          nixoa_print_error "host show accepts only one hostname."
          exit 1
        fi
        target="$1"
        shift
        ;;
    esac
  done

  target="${target:-$(nixoa_default_target)}"

  resolved_target="$(nixoa_require_target_output "$target")"
  host_name="$(nixoa_resolve_target_host "$resolved_target")"
  host_dir="$(nixoa_resolve_host_dir "$host_name")"
  settings_file="$(nixoa_host_settings_file "$host_name")"
  menu_file="$(nixoa_host_menu_file "$host_name")"
  selected_vm="$(nixoa_vm_alias_host || true)"
  username="$(nixoa_config_string username "$host_name" || true)"
  timezone="$(nixoa_config_string timezone "$host_name" || true)"
  profile="$(nixoa_config_string deploymentProfile "$host_name" || true)"
  repo_dir="$(nixoa_config_string repoDir "$host_name" || true)"

  if [ "$json" -eq 1 ]; then
    printf '{\n'
    printf '  "host": %s,\n' "$(nxcli_json_quote "$host_name")"
    printf '  "directory": %s,\n' "$(nxcli_json_quote "${host_dir#"$NIXOA_SYSTEM_ROOT/"}")"
    printf '  "profile": %s,\n' "$(nxcli_json_quote "${profile:-unknown}")"
    printf '  "username": %s,\n' "$(nxcli_json_quote "${username:-unknown}")"
    printf '  "timezone": %s,\n' "$(nxcli_json_quote "${timezone:-unknown}")"
    printf '  "repoDir": %s,\n' "$(nxcli_json_quote "${repo_dir:-unknown}")"
    printf '  "vmSelected": %s,\n' "$( [ "$host_name" = "$selected_vm" ] && printf true || printf false )"
    printf '  "outputs": [%s, %s],\n' "$(nxcli_json_quote "$host_name")" "$(nxcli_json_quote "$host_name-vm")"
    printf '  "settingsFile": %s,\n' "$(nxcli_json_quote "${settings_file#"$NIXOA_SYSTEM_ROOT/"}")"
    printf '  "menuFile": %s\n' "$(nxcli_json_quote "${menu_file#"$NIXOA_SYSTEM_ROOT/"}")"
    printf '}\n'
    return 0
  fi

  printf 'Host: %s\n' "$host_name"
  printf 'Directory: %s\n' "${host_dir#"$NIXOA_SYSTEM_ROOT/"}"
  printf 'Profile: %s\n' "${profile:-unknown}"
  printf 'Username: %s\n' "${username:-unknown}"
  printf 'Timezone: %s\n' "${timezone:-unknown}"
  printf 'Repo dir: %s\n' "${repo_dir:-unknown}"
  printf 'Stable vm alias: %s\n' "$( [ "$host_name" = "$selected_vm" ] && printf 'selected' || printf 'not selected' )"
  printf 'Concrete outputs: %s, %s-vm\n' "$host_name" "$host_name"
  printf 'Settings file: %s\n' "${settings_file#"$NIXOA_SYSTEM_ROOT/"}"
  printf 'Menu file: %s\n' "${menu_file#"$NIXOA_SYSTEM_ROOT/"}"
}

host_select_vm() {
  local host_name="$1"

  host_name="$(nixoa_resolve_target_host "$(nixoa_require_target_output "$host_name")")"
  nixoa_write_vm_alias_settings "$(nixoa_vm_alias_file)" "$host_name"
  git -C "$NIXOA_SYSTEM_ROOT" add host/_automation/default.nix
  nixoa_print_success "Stable vm alias now points to ${host_name}-vm."
}

host_edit() {
  local target="${1:-$(nixoa_default_target)}"
  local resolved_target=""
  local host_name=""
  local editor=""

  resolved_target="$(nixoa_require_target_output "$target")"
  host_name="$(nixoa_resolve_target_host "$resolved_target")"
  editor="$(nixoa_default_editor)"

  exec "$editor" \
    "$(nixoa_host_settings_file "$host_name")" \
    "$(nixoa_host_menu_file "$host_name")"
}

host_add() {
  local hostname_arg=""
  local profile_arg=""
  local username_arg=""
  local git_name_arg=""
  local git_email_arg=""
  local timezone_arg=""
  local state_version_arg=""
  local copy_hardware=""
  local set_vm_alias=1
  local skip_check=0
  local first_switch=0
  local switch_now=0
  local extra_ssh_key=""
  local template_dir=""
  local host_dir=""
  local settings_file=""
  local hardware_file=""
  local default_profile=""
  local ssh_key=""
  declare -a ssh_keys=()

  if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
    hostname_arg="$1"
    shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --profile)
        profile_arg="$2"
        shift 2
        ;;
      --copy-hardware)
        copy_hardware=1
        shift
        ;;
      --skip-hardware-copy)
        copy_hardware=0
        shift
        ;;
      --set-vm-alias)
        set_vm_alias=1
        shift
        ;;
      --no-set-vm-alias)
        set_vm_alias=0
        shift
        ;;
      --username)
        username_arg="$2"
        shift 2
        ;;
      --git-name)
        git_name_arg="$2"
        shift 2
        ;;
      --git-email)
        git_email_arg="$2"
        shift 2
        ;;
      --timezone)
        timezone_arg="$2"
        shift 2
        ;;
      --state-version)
        state_version_arg="$2"
        shift 2
        ;;
      --ssh-key)
        ssh_keys+=("$2")
        shift 2
        ;;
      --skip-check)
        skip_check=1
        shift
        ;;
      --first-switch)
        first_switch=1
        shift
        ;;
      --help)
        show_host_add_help
        exit 0
        ;;
      *)
        nixoa_print_error "Unknown host add option: $1"
        exit 1
        ;;
    esac
  done

  nixoa_require_git_repo
  nixoa_cd_root
  nixoa_require_clean_repo

  default_profile="$(nixoa_detect_default_profile)"

  if [ -z "$hostname_arg" ]; then
    hostname_arg="$(nixoa_prompt_with_default "Hostname" "$NIXOA_DEFAULT_HOSTNAME")"
  fi
  nixoa_validate_hostname "$hostname_arg"

  if [ -z "$profile_arg" ]; then
    profile_arg="$(nixoa_prompt_with_default "Deployment profile (physical|vm)" "$default_profile")"
  fi
  profile_arg="$(nixoa_normalize_profile "$profile_arg")"

  if [ -z "$copy_hardware" ]; then
    copy_hardware=1
  fi

  if [ -z "$username_arg" ]; then
    username_arg="$(nixoa_prompt_with_default "Username" "$NIXOA_DEFAULT_USERNAME")"
  fi
  nixoa_validate_username "$username_arg"

  if [ -z "$git_name_arg" ]; then
    git_name_arg="$(nixoa_prompt_with_default "Git user.name" "$NIXOA_DEFAULT_GIT_NAME")"
  fi

  if [ -z "$git_email_arg" ]; then
    git_email_arg="$(nixoa_prompt_with_default "Git user.email" "$NIXOA_DEFAULT_GIT_EMAIL")"
  fi

  if [ -z "$timezone_arg" ]; then
    timezone_arg="$(nixoa_prompt_with_default "Time zone" "$NIXOA_DEFAULT_TIMEZONE")"
  fi

  if [ -z "$state_version_arg" ]; then
    state_version_arg="$(nixoa_prompt_with_default "State version" "25.11")"
  fi

  if [ "${#ssh_keys[@]}" -eq 0 ]; then
    ssh_keys+=( "$(nixoa_prompt_required "SSH public key")" )
  fi

  while true; do
    extra_ssh_key="$(nixoa_prompt_optional "Additional SSH public key [leave blank to finish]")"
    [ -n "$extra_ssh_key" ] || break
    ssh_keys+=("$extra_ssh_key")
  done

  template_dir="$NIXOA_HOST_ROOT/$NIXOA_TEMPLATE_HOST"
  host_dir="$NIXOA_HOST_ROOT/$hostname_arg"
  settings_file="$host_dir/_ctx/settings.nix"
  hardware_file="$host_dir/_nixos/hardware-configuration.nix"

  if [ ! -d "$template_dir" ]; then
    nixoa_print_error "Host template not found at ${template_dir#"$NIXOA_SYSTEM_ROOT/"}."
    exit 1
  fi

  if [ "$copy_hardware" -eq 1 ] && [ ! -f /etc/nixos/hardware-configuration.nix ]; then
    nixoa_print_error "/etc/nixos/hardware-configuration.nix was not found."
    nixoa_print_error "Bootstrap expects to copy the machine's hardware configuration into ${hardware_file#"$NIXOA_SYSTEM_ROOT/"}."
    nixoa_print_error "If you really want to proceed without it, rerun with --skip-hardware-copy and replace the placeholder file manually."
    exit 1
  fi

  if [ -e "$host_dir" ]; then
    nixoa_print_error "Host directory ${host_dir#"$NIXOA_SYSTEM_ROOT/"} already exists."
    exit 1
  fi

  printf 'Repository: %s\n' "$NIXOA_SYSTEM_ROOT"
  printf 'Host directory: %s\n' "${host_dir#"$NIXOA_SYSTEM_ROOT/"}"
  printf 'Hostname: %s\n' "$hostname_arg"
  printf 'Username: %s\n' "$username_arg"
  printf 'Profile: %s\n' "$profile_arg"
  printf 'Copy hardware: %s\n' "$( [ "$copy_hardware" -eq 1 ] && printf 'yes' || printf 'no' )"
  printf 'Set stable vm alias: %s\n' "$( [ "$set_vm_alias" -eq 1 ] && printf 'yes' || printf 'no' )"
  printf 'SSH keys: %s\n' "${#ssh_keys[@]}"
  if [ "$set_vm_alias" -eq 1 ]; then
    printf 'Stable vm target: vm -> %s-vm\n' "$hostname_arg"
  fi

  if ! nixoa_confirm "Create this host"; then
    nixoa_print_warning "Host creation cancelled."
    exit 1
  fi

  cp -r "$template_dir" "$host_dir"
  nixoa_write_host_settings \
    "$settings_file" \
    "$hostname_arg" \
    "$profile_arg" \
    "$NIXOA_SYSTEM_ROOT" \
    "$timezone_arg" \
    "$state_version_arg" \
    "$username_arg" \
    "$git_name_arg" \
    "$git_email_arg" \
    ssh_keys

  if [ "$copy_hardware" -eq 1 ]; then
    install -m 0644 /etc/nixos/hardware-configuration.nix "$hardware_file"
  fi

  if [ "$set_vm_alias" -eq 1 ]; then
    nixoa_write_vm_alias_settings "$(nixoa_vm_alias_file)" "$hostname_arg"
    git -C "$NIXOA_SYSTEM_ROOT" add "host/$hostname_arg" "host/_automation/default.nix"
  else
    git -C "$NIXOA_SYSTEM_ROOT" add "host/$hostname_arg"
  fi

  if [ "$skip_check" -eq 0 ]; then
    if [ "$first_switch" -eq 1 ]; then
      nixoa_print_info "Running nix flake check --no-write-lock-file with first-install cache options"
      nixoa_run_first_install_flake_check
    else
      nixoa_print_info "Running nix flake check --no-write-lock-file"
      nix flake check --no-write-lock-file "path:$NIXOA_SYSTEM_ROOT"
    fi
  fi

  if [ "$first_switch" -eq 1 ]; then
    switch_now=1
  elif [ -t 0 ]; then
    if nixoa_confirm "Switch to the new flake now"; then
      switch_now=1
    fi
  fi

  if [ "$switch_now" -eq 1 ]; then
    nixoa_print_info "Switching to the new flake now. The initial install uses nixos-rebuild with first-install cache settings; later applies use nh."
    if nixoa_user_exists "$username_arg"; then
      NIXOA_NH_USER="$username_arg" "$NIXOA_SYSTEM_ROOT/scripts/nxcli.sh" apply --target "$hostname_arg" --first-install
    else
      "$NIXOA_SYSTEM_ROOT/scripts/nxcli.sh" apply --target "$hostname_arg" --first-install
    fi
  fi

  nixoa_print_success "Created host/$hostname_arg."
  nixoa_print_cli_command "Next:" host show "$hostname_arg"
  if [ "$switch_now" -eq 1 ]; then
    printf 'Initial apply completed for target %s.\n' "$hostname_arg"
  else
    nixoa_print_info "Initial switch skipped."
    nixoa_print_first_switch_commands "$hostname_arg"
  fi
  nixoa_print_cli_command "Stable vm target:" apply --target vm
}

commit_changes() {
  local commit_message=""

  case "${1:-}" in
    --help|-h)
      show_commit_help
      return 0
      ;;
  esac

  commit_message="$*"

  nixoa_require_git_repo
  nixoa_cd_root

  if ! nixoa_has_changes; then
    echo "No changes to commit."
    return 0
  fi

  nixoa_print_change_summary
  nixoa_stage_changes

  if ! nixoa_has_staged_changes; then
    echo "No staged changes were produced."
    return 0
  fi

  nixoa_commit_changes "$commit_message"

  echo "✓ Repository changes committed successfully!"
  echo ""
  echo "To undo this commit: git reset HEAD~1"
}

show_diff() {
  local json=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --help|-h)
        echo "Usage: nxcli diff [--json]" >&2
        return 0
        ;;
      *)
        nixoa_print_error "Unknown diff option: $1"
        exit 1
        ;;
    esac
  done

  nixoa_require_git_repo
  nixoa_cd_root

  if [ "$json" -eq 1 ]; then
    show_diff_json
    return 0
  fi

  echo "=== Uncommitted Changes ==="
  git diff HEAD -- "${NIXOA_TRACKED_PATHS[@]}"
  echo ""
  echo "=== Git Status ==="
  nixoa_status_porcelain || true

  if [ -z "$(nixoa_status_porcelain)" ]; then
    echo "No uncommitted changes."
  fi
}

show_history() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: nxcli history" >&2
      return 0
      ;;
  esac

  if [ $# -gt 0 ]; then
    nixoa_print_error "Unknown history option: $1"
    exit 1
  fi

  nixoa_require_git_repo
  nixoa_cd_root

  echo "=== NiXOA Repository History ==="
  git log --oneline --decorate --graph -10 -- "${NIXOA_TRACKED_PATHS[@]}"

  echo ""
  echo "To see full diff for a commit: git show <commit-hash>"
  echo "To restore paths from a commit: git restore --source <commit-hash> -- ${NIXOA_TRACKED_PATHS[*]}"
}

run_apply_config() {
  local target_arg="${NIXOA_HOSTNAME:-$(nixoa_default_target)}"
  local rebuild_action="switch"
  local record_action="switch"
  local first_install=0
  local first_install_switch=0
  local rollback=0
  local dry_run=0
  local ask=0
  local verbose=0
  local cores=""
  local current_head=""
  local exit_code=0
  local nh_user=""
  local sudo_bin=""
  local -a extra_args=()
  local -a build_extra_args=()
  local -a rebuild_cmd=()
  local -a run_rebuild=()

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
      --help|-h)
        show_apply_help
        return 0
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
  elif nixoa_has_changes; then
    nixoa_print_warning "Tracked NiXOA files are dirty; proceeding with the current working tree."
  fi

  current_head="$(git -C "$NIXOA_SYSTEM_ROOT" rev-parse HEAD 2>/dev/null || true)"

  if [ "$first_install" -eq 1 ] && [ "$rollback" -eq 0 ] && [ "$dry_run" -eq 0 ] && [ "$rebuild_action" = "switch" ]; then
    first_install_switch=1
  elif [ "$first_install" -eq 1 ]; then
    nixoa_append_first_install_nix_options build_extra_args
  fi

  build_extra_args+=("${extra_args[@]}")

  if [ "$rollback" -eq 0 ] && [ "$first_install_switch" -eq 0 ] && [ "$EUID" -eq 0 ] && [ -z "${NIXOA_NH_USER:-}" ]; then
    nh_user="$(nixoa_host_execution_user "$target_arg" || true)"
    if [ -n "$nh_user" ]; then
      export NIXOA_NH_USER="$nh_user"
    fi
    export NIXOA_NH_TARGET="$target_arg"
  fi

  if [ "$rollback" -eq 1 ]; then
    rebuild_cmd=(
      nixos-rebuild
      switch
      --rollback
      -L
    )
  elif [ "$first_install_switch" -eq 1 ]; then
    nixoa_build_first_install_switch_command rebuild_cmd "$target_arg"
    if [ "${#extra_args[@]}" -gt 0 ]; then
      rebuild_cmd+=("${extra_args[@]}")
    fi
  else
    nixoa_build_nh_command rebuild_cmd "$rebuild_action" "$target_arg" "$ask" "$cores" "$verbose"
    if [ "$dry_run" -eq 1 ]; then
      rebuild_cmd+=(--dry)
    fi
    if [ "${#build_extra_args[@]}" -gt 0 ]; then
      rebuild_cmd+=(-- "${build_extra_args[@]}")
    fi
  fi

  printf 'Running:'
  if [ "$rollback" -eq 0 ] && [ "$first_install_switch" -eq 0 ]; then
    printf ' %q' nh
  else
    if [ "$EUID" -ne 0 ]; then
      sudo_bin="$(nixoa_sudo_bin)" || exit 1
      rebuild_cmd=("$sudo_bin" "${rebuild_cmd[@]}")
    fi
  fi
  printf ' %q' "${rebuild_cmd[@]}"
  printf '\n'

  if [ "$rollback" -eq 1 ] || [ "$first_install_switch" -eq 1 ]; then
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
}

preview_flake_update() {
  local tmp_lock=""
  local -a update_inputs=("$@")

  nixoa_cd_root
  tmp_lock="$(mktemp)"
  cp flake.lock "$tmp_lock"

  if [ "${#update_inputs[@]}" -gt 0 ]; then
    nix flake update --output-lock-file "$tmp_lock" "${update_inputs[@]}"
  else
    nix flake update --output-lock-file "$tmp_lock"
  fi

  if git -C "$NIXOA_SYSTEM_ROOT" diff --no-index --quiet -- flake.lock "$tmp_lock"; then
    nixoa_print_success "No lock-file changes found."
  else
    nixoa_print_info "Lock-file diff preview:"
    git -C "$NIXOA_SYSTEM_ROOT" diff --no-index -- flake.lock "$tmp_lock" || true
  fi

  rm -f "$tmp_lock"
}

update_flake() {
  local target_arg="$(nixoa_default_target)"
  local ask=0
  local preview=0

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
      --preview)
        preview=1
        shift
        ;;
      --help)
        show_update_help
        exit 0
        ;;
      *)
        nixoa_print_error "Unknown update flake option: $1"
        exit 1
        ;;
    esac
  done

  target_arg="$(nixoa_require_target_output "$target_arg")"

  if [ "$ask" -eq 1 ] && ! nixoa_confirm "Update all flake inputs in this repo"; then
    nixoa_print_warning "Update cancelled."
    exit 1
  fi

  nixoa_require_git_repo
  nixoa_cd_root
  if [ "$preview" -eq 1 ]; then
    preview_flake_update
    nixoa_print_success "Flake update preview completed without changing files."
    return 0
  fi

  nix flake update
  nixoa_print_success "Flake inputs updated."
  if ! git -C "$NIXOA_SYSTEM_ROOT" diff --quiet -- flake.lock; then
    nixoa_print_cli_command "Save changes:" commit "Update flake inputs"
  fi
  nixoa_print_cli_command "Next:" apply --target "$target_arg"
  nixoa_print_cli_command "Safer path:" boot --target "$target_arg"
}

update_xoa() {
  local target_arg="$(nixoa_default_target)"
  local ask=0
  local preview=0
  local old_rev=""
  local new_rev=""
  local tmp_dir=""

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
      --preview)
        preview=1
        shift
        ;;
      --help)
        show_update_help
        exit 0
        ;;
      *)
        nixoa_print_error "Unknown xoa update option: $1"
        exit 1
        ;;
    esac
  done

  nixoa_require_git_repo
  nixoa_cd_root
  target_arg="$(nixoa_require_target_output "$target_arg")"

  if [ "$ask" -eq 1 ] && ! nixoa_confirm "Update the xen-orchestra-ce flake input"; then
    nixoa_print_warning "XOA update cancelled."
    exit 1
  fi

  old_rev="$(jq -r '.nodes."xen-orchestra-ce".locked.rev // empty' flake.lock 2>/dev/null || true)"

  if [ "$preview" -eq 1 ]; then
    preview_flake_update xen-orchestra-ce
    nixoa_print_success "xen-orchestra-ce update preview completed without changing files."
    return 0
  fi

  if nixoa_has_changes; then
    nixoa_print_error "Tracked NiXOA files are dirty; commit or stash them before nxcli update xoa."
    exit 1
  fi

  nixoa_print_info "Updating xen-orchestra-ce input"
  nix flake update xen-orchestra-ce

  new_rev="$(jq -r '.nodes."xen-orchestra-ce".locked.rev // empty' flake.lock 2>/dev/null || true)"
  if [ -z "$new_rev" ]; then
    nixoa_print_error "Could not read the new xen-orchestra-ce revision from flake.lock."
    exit 1
  fi

  printf 'xen-orchestra-ce: %s -> %s\n' "${old_rev:-<none>}" "$new_rev"

  if ! git -C "$NIXOA_SYSTEM_ROOT" diff --quiet -- flake.lock; then
    git -C "$NIXOA_SYSTEM_ROOT" add flake.lock
    nixoa_commit_changes "Update xen-orchestra-ce input"
    nixoa_print_success "Committed updated xen-orchestra-ce lock entry."
  else
    nixoa_print_success "xen-orchestra-ce was already current."
  fi

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
}

show_status() {
  local json=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --json)
        json=1
        shift
        ;;
      --help|-h)
        echo "Usage: nxcli status [--json]" >&2
        return 0
        ;;
      *)
        nixoa_print_error "Unknown status option: $1"
        exit 1
        ;;
    esac
  done

  if [ "$json" -eq 1 ]; then
    show_status_json
  else
    nixoa_render_status
  fi
}

list_generations() {
  nixoa_run_as_root nix-env --list-generations -p /nix/var/nix/profiles/system
}

dispatch_host() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    add)
      host_add "$@"
      ;;
    list)
      host_list "$@"
      ;;
    show)
      host_show "$@"
      ;;
    select-vm)
      if [ $# -lt 1 ]; then
        nixoa_print_error "host select-vm requires a hostname."
        exit 1
      fi
      host_select_vm "$1"
      ;;
    edit)
      host_edit "${1:-}"
      ;;
    help|--help|-h)
      show_host_help
      ;;
    *)
      nixoa_print_error "Unknown host command: ${subcommand:-<missing>}"
      exit 1
      ;;
  esac
}

dispatch_update() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    flake)
      update_flake "$@"
      ;;
    xoa)
      update_xoa "$@"
      ;;
    help|--help|-h)
      show_update_help
      ;;
    *)
      nixoa_print_error "Unknown update command: ${subcommand:-<missing>}"
      exit 1
      ;;
  esac
}

dispatch_xo() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    logs)
      exec "$NIXOA_SYSTEM_ROOT/scripts/xoa-logs.sh" "$@"
      ;;
    help|--help|-h)
      show_xo_help
      ;;
    *)
      nixoa_print_error "Unknown xo command: ${subcommand:-<missing>}"
      exit 1
      ;;
  esac
}

dispatch_generations() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    list)
      list_generations
      ;;
    help|--help|-h)
      show_generations_help
      ;;
    *)
      nixoa_print_error "Unknown generations command: ${subcommand:-<missing>}"
      exit 1
      ;;
  esac
}

main() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    help|--help|-h)
      show_help
      ;;
    version)
      show_version
      ;;
    status)
      show_status "$@"
      ;;
    apply)
      run_apply_config "$@"
      ;;
    boot)
      run_apply_config --boot "$@"
      ;;
    rollback)
      run_apply_config --rollback "$@"
      ;;
    commit)
      commit_changes "$@"
      ;;
    diff)
      show_diff "$@"
      ;;
    history)
      show_history "$@"
      ;;
    host)
      dispatch_host "$@"
      ;;
    update)
      dispatch_update "$@"
      ;;
    xo)
      dispatch_xo "$@"
      ;;
    generations)
      dispatch_generations "$@"
      ;;
    *)
      nixoa_print_error "Unknown command: $command"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
