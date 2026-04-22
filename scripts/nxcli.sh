#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Canonical NiXOA operator CLI

set -euo pipefail

readonly NXCLI_VERSION="4.0.0"

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
  nxcli status
  nxcli apply [--target <hostname|vm>] [--build|--dry-run|--first-install] [--ask] [--cores N] [--verbose] [--no-nom] [-- ...]
  nxcli boot [--target <hostname|vm>] [--ask] [--cores N] [--verbose] [--no-nom] [-- ...]
  nxcli rollback [--target <hostname|vm>]
  nxcli host add [hostname] [--profile physical|vm] [--copy-hardware|--skip-hardware-copy] [--set-vm-alias|--no-set-vm-alias]
  nxcli host list
  nxcli host show [hostname]
  nxcli host select-vm <hostname>
  nxcli host edit [hostname]
  nxcli update flake
  nxcli update xoa
  nxcli xo logs
  nxcli generations list

Shared rebuild flags:
  --target <hostname|vm>   Canonical target selector. Accepts <hostname>, <hostname>-vm, or vm.
  --ask                    Ask nh for confirmation before mutating actions.
  --cores N                Pass through a core limit to nh.
  --verbose                Increase nh verbosity.
  --no-nom                 Disable nix-output-monitor for nh.

Notes:
  - host/_automation/default.nix is the stable vm selector behind --target vm.
  - Lower-level scripts remain in scripts/, but nxcli is the supported operator interface.
EOF
}

show_host_help() {
  cat <<'EOF'
Usage:
  nxcli host add [hostname] [options]
  nxcli host list
  nxcli host show [hostname]
  nxcli host select-vm <hostname>
  nxcli host edit [hostname]
EOF
}

show_host_add_help() {
  cat <<'EOF'
Usage: nxcli host add [hostname] [options]

Options:
  --profile NAME           Deployment profile: physical or vm. Defaults from virtualization detection.
  --copy-hardware          Copy /etc/nixos/hardware-configuration.nix into the new host tree.
  --skip-hardware-copy     Do not copy the local hardware profile.
  --set-vm-alias           Update host/_automation/default.nix to point vm at this host. Default: yes.
  --no-set-vm-alias        Leave the stable vm alias unchanged.
  --no-nom                 Use --no-nom for the optional first switch after host creation.
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
  nxcli update flake [--target <hostname|vm>] [--ask]
  nxcli update xoa [--target <hostname|vm>] [--ask]
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

host_list() {
  local selected_vm=""
  local host_dir=""
  local host_name=""
  local profile=""

  selected_vm="$(nixoa_vm_alias_host || true)"

  while IFS= read -r host_dir; do
    [ -n "$host_dir" ] || continue
    host_name="$(basename "$host_dir")"
    profile="$(nixoa_config_string deploymentProfile "$host_name" || true)"
    if [ "$host_name" = "$selected_vm" ]; then
      printf '%s\tprofile=%s\tvm=selected\n' "$host_name" "${profile:-unknown}"
    else
      printf '%s\tprofile=%s\n' "$host_name" "${profile:-unknown}"
    fi
  done < <(nixoa_existing_host_dirs)
}

host_show() {
  local target="${1:-$(nixoa_default_target)}"
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
    "$(nixoa_host_menu_file "$host_name")" \
    "$NIXOA_SYSTEM_ROOT/config.nixoa.toml"
}

host_add() {
  local hostname_arg="${1:-}"
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
  local no_nom=0
  local switch_now=0
  local extra_ssh_key=""
  local template_dir=""
  local host_dir=""
  local settings_file=""
  local hardware_file=""
  local default_profile=""
  local ssh_key=""
  declare -a ssh_keys=()

  shift || true

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
      --no-nom)
        no_nom=1
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
    if [ "$profile_arg" = "physical" ]; then
      copy_hardware=1
    else
      copy_hardware=0
    fi
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
    if [ -f /etc/nixos/hardware-configuration.nix ]; then
      install -m 0644 /etc/nixos/hardware-configuration.nix "$hardware_file"
    else
      nixoa_print_warning "/etc/nixos/hardware-configuration.nix was not found; leaving the template file in place."
    fi
  fi

  if [ "$set_vm_alias" -eq 1 ]; then
    nixoa_write_vm_alias_settings "$(nixoa_vm_alias_file)" "$hostname_arg"
    git -C "$NIXOA_SYSTEM_ROOT" add "host/$hostname_arg" "host/_automation/default.nix"
  else
    git -C "$NIXOA_SYSTEM_ROOT" add "host/$hostname_arg"
  fi

  if [ "$skip_check" -eq 0 ]; then
    nixoa_print_info "Running nix flake check --no-write-lock-file"
    nix flake check --no-write-lock-file "path:$NIXOA_SYSTEM_ROOT"
  fi

  if [ "$first_switch" -eq 1 ]; then
    switch_now=1
  elif [ -t 0 ]; then
    if nixoa_confirm "Switch to the new flake now"; then
      switch_now=1
    fi
  fi

  if [ "$switch_now" -eq 1 ]; then
    nixoa_print_info "Switching to the new flake now. This uses nh and falls back to 'nix shell nixpkgs#nh -c nh' if nh is not installed yet."
    if nixoa_user_exists "$username_arg"; then
      if [ "$no_nom" -eq 1 ]; then
        NIXOA_NH_USER="$username_arg" "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --target "$hostname_arg" --first-install --no-nom
      else
        NIXOA_NH_USER="$username_arg" "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --target "$hostname_arg" --first-install
      fi
    else
      if [ "$no_nom" -eq 1 ]; then
        "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --target "$hostname_arg" --first-install --no-nom
      else
        "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --target "$hostname_arg" --first-install
      fi
    fi
  fi

  nixoa_print_success "Created host/$hostname_arg."
  nixoa_print_cli_command "Next:" host show "$hostname_arg"
  if [ "$switch_now" -eq 1 ]; then
    printf 'Initial apply completed for target %s.\n' "$hostname_arg"
  else
    nixoa_print_info "Initial switch skipped."
    nixoa_print_first_switch_commands "$hostname_arg" "$no_nom"
  fi
  nixoa_print_cli_command "Stable vm target:" apply --target vm
}

update_flake() {
  local target_arg="$(nixoa_default_target)"
  local ask=0

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
  nix flake update
  nixoa_print_success "Flake inputs updated."
  nixoa_print_cli_command "Next:" apply --target "$target_arg"
  nixoa_print_cli_command "Safer path:" boot --target "$target_arg"
}

update_xoa() {
  exec "$NIXOA_SYSTEM_ROOT/scripts/xoa-update.sh" "$@"
}

show_status() {
  nixoa_render_status
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
      host_list
      ;;
    show)
      host_show "${1:-}"
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
      show_status
      ;;
    apply)
      exec "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" "$@"
      ;;
    boot)
      exec "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --boot "$@"
      ;;
    rollback)
      exec "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --rollback "$@"
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
