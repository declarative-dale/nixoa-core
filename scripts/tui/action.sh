#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

nixoa_require_git_repo
nixoa_cd_root

usage() {
  cat <<'EOF'
Usage: action.sh <command> [value]

Commands:
  set-hostname VALUE
  set-username VALUE
  set-ssh-key VALUE
  add-ssh-key VALUE
  remove-ssh-key VALUE
  toggle-extras
  add-system-package VALUE
  add-user-package VALUE
  add-service VALUE
  update-nixpkgs
  update-home-manager
  update-determinate
  update-xoa
  update-all
  cleanup-unmanaged-users
EOF
}

load_state() {
  hostname_value="$(nixoa_tui_hostname)"
  username_value="$(nixoa_tui_username)"
  timezone_value="$(nixoa_tui_timezone)"
  extras_value="$(nixoa_tui_enable_extras)"

  mapfile -t ssh_keys_value < <(nixoa_tui_ssh_keys)
  mapfile -t system_packages_value < <(nixoa_tui_extra_system_packages)
  mapfile -t user_packages_value < <(nixoa_tui_extra_user_packages)
  mapfile -t services_value < <(nixoa_tui_enabled_services)
}

commit_lock_if_changed() {
  local message="$1"

  if [ -z "$(git -C "$NIXOA_SYSTEM_ROOT" status --short -- flake.lock)" ]; then
    echo "No flake.lock changes were produced."
    return 1
  fi

  nixoa_tui_commit_paths "$message" flake.lock
}

prompt_yes_no() {
  local prompt="$1"
  local reply=""

  if [ ! -t 0 ]; then
    return 1
  fi

  read -r -p "$prompt [y/N]: " reply
  case "$reply" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_rebuild_policy() {
  local target_value="${1:-$(nixoa_default_target)}"
  target_value="$(nixoa_host_output_name "$target_value")"

  if prompt_yes_no "Rebuild now"; then
    "$NIXOA_SYSTEM_ROOT/scripts/apply-config.sh" --hostname "$target_value"
    return 0
  fi

  if prompt_yes_no "Queue rebuild for next boot"; then
    nixoa_schedule_rebuild_on_boot "$NIXOA_SYSTEM_ROOT" "$target_value"
    echo "Queued a rebuild for the next boot."
    return 0
  fi

  echo "Skipped rebuild."
}

update_input_and_prompt() {
  local commit_message="$1"
  shift

  "$@"

  if commit_lock_if_changed "$commit_message"; then
    prompt_rebuild_policy "$(nixoa_default_target)"
  fi
}

lock_rev_for() {
  local node_name="$1"

  awk -v node_name="$node_name" '
    BEGIN {
      in_node = 0
      in_locked = 0
    }
    $0 ~ "^[[:space:]]*\"" node_name "\"[[:space:]]*:[[:space:]]*\\{" {
      in_node = 1
      next
    }
    in_node && $0 ~ /^[[:space:]]*"locked"[[:space:]]*:[[:space:]]*\{/ {
      in_locked = 1
      next
    }
    in_node && in_locked && $0 ~ /^[[:space:]]*"rev"[[:space:]]*:/ {
      line = $0
      sub(/^[[:space:]]*"rev"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/",?[[:space:]]*$/, "", line)
      print line
      exit
    }
    in_node && in_locked && $0 ~ /^[[:space:]]*}[,]?[[:space:]]*$/ {
      in_locked = 0
    }
  ' "$NIXOA_SYSTEM_ROOT/flake.lock"
}

lock_url_for() {
  local node_name="$1"

  awk -v node_name="$node_name" '
    BEGIN {
      in_node = 0
      in_original = 0
    }
    $0 ~ "^[[:space:]]*\"" node_name "\"[[:space:]]*:[[:space:]]*\\{" {
      in_node = 1
      next
    }
    in_node && $0 ~ /^[[:space:]]*"original"[[:space:]]*:[[:space:]]*\{/ {
      in_original = 1
      next
    }
    in_node && in_original && $0 ~ /^[[:space:]]*"url"[[:space:]]*:/ {
      line = $0
      sub(/^[[:space:]]*"url"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/",?[[:space:]]*$/, "", line)
      print line
      exit
    }
    in_node && in_original && $0 ~ /^[[:space:]]*}[,]?[[:space:]]*$/ {
      in_original = 0
    }
  ' "$NIXOA_SYSTEM_ROOT/flake.lock"
}

normalize_git_remote() {
  local url="$1"

  url="${url#git+}"
  url="${url%%\?*}"
  printf '%s\n' "$url"
}

latest_xoa_tag() {
  local remote_url="$1"

  git ls-remote --tags --refs "$remote_url" \
    | awk '{ sub("refs/tags/", "", $2); print $2, $1 }' \
    | sort -V \
    | tail -n 1
}

cleanup_unmanaged_users() {
  local managed_user="$1"
  local passwd_line=""
  local username=""
  local home_dir=""
  local -a targets=()
  local -a homes=()
  local entry=""
  local dir=""
  local total_targets=0
  local current_target=0
  local removed_users=0
  local removed_orphans=0

  echo "[1/4] Scanning for unmanaged users under /home..."

  while IFS=: read -r username _ _ _ _ home_dir _; do
    [ -n "$username" ] || continue
    [ "$username" = "$managed_user" ] && continue
    case "$home_dir" in
      /home/*)
        targets+=("$username")
        homes+=("$home_dir")
        ;;
    esac
  done < <(getent passwd)

  total_targets="${#targets[@]}"

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "No unmanaged users under /home were found."
  else
    echo "[2/4] Removing unmanaged users:"
    printf '  - %s\n' "${targets[@]}"

    local i
    for i in "${!targets[@]}"; do
      username="${targets[$i]}"
      home_dir="${homes[$i]}"
      current_target=$((i + 1))

      printf '[2/4] [%d/%d] Removing user %s and home %s\n' \
        "$current_target" "$total_targets" "$username" "$home_dir"

      loginctl terminate-user "$username" >/dev/null 2>&1 || true
      loginctl disable-linger "$username" >/dev/null 2>&1 || true
      pkill -KILL -u "$username" >/dev/null 2>&1 || true

      if id "$username" >/dev/null 2>&1; then
        userdel --remove "$username"
      fi

      if [ -d "$home_dir" ]; then
        rm -rf --one-file-system "$home_dir"
      fi

      removed_users=$((removed_users + 1))
    done
  fi

  echo "[3/4] Removing orphan home directories..."
  for dir in /home/*; do
    [ -d "$dir" ] || continue
    [ "$dir" = "/home/$managed_user" ] && continue

    entry="$(getent passwd "$(basename "$dir")" || true)"
    if [ -z "$entry" ]; then
      echo "Removing orphan home directory: $dir"
      rm -rf --one-file-system "$dir"
      removed_orphans=$((removed_orphans + 1))
    fi
  done

  echo "[4/4] Cleanup complete."
  printf 'Removed %d unmanaged users and %d orphan home directories.\n' \
    "$removed_users" "$removed_orphans"
}

if [ $# -lt 1 ]; then
  usage >&2
  exit 1
fi

command_name="$1"
shift

load_state
host_menu_relpath="$(nixoa_host_relpath)/_ctx/menu.nix"

case "$command_name" in
  set-hostname)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_token "hostname" "$1"
    hostname_value="$1"
    nixoa_tui_write_menu \
      "$hostname_value" \
      "$username_value" \
      "$timezone_value" \
      "$extras_value" \
      ssh_keys_value \
      system_packages_value \
      user_packages_value \
      services_value
    nixoa_tui_commit_paths "Set hostname to ${hostname_value} from nixoa-menu" "$host_menu_relpath"
    ;;
  set-username)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_token "username" "$1"
    username_value="$1"
    nixoa_tui_write_menu \
      "$hostname_value" \
      "$username_value" \
      "$timezone_value" \
      "$extras_value" \
      ssh_keys_value \
      system_packages_value \
      user_packages_value \
      services_value
    nixoa_tui_commit_paths "Set username to ${username_value} from nixoa-menu" "$host_menu_relpath"
    ;;
  set-ssh-key)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_ssh_key "$1"
    ssh_keys_value=("$1")
    nixoa_tui_write_menu \
      "$hostname_value" \
      "$username_value" \
      "$timezone_value" \
      "$extras_value" \
      ssh_keys_value \
      system_packages_value \
      user_packages_value \
      services_value
    nixoa_tui_commit_paths "Set SSH key from nixoa-menu" "$host_menu_relpath"
    ;;
  add-ssh-key)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_ssh_key "$1"
    if nixoa_tui_append_unique "$1" ssh_keys_value; then
      nixoa_tui_write_menu \
        "$hostname_value" \
        "$username_value" \
        "$timezone_value" \
        "$extras_value" \
        ssh_keys_value \
        system_packages_value \
        user_packages_value \
        services_value
      nixoa_tui_commit_paths "Add SSH key from nixoa-menu" "$host_menu_relpath"
    else
      echo "SSH key already present."
    fi
    ;;
  remove-ssh-key)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    if nixoa_tui_remove_value "$1" ssh_keys_value; then
      if [ "${#ssh_keys_value[@]}" -eq 0 ]; then
        echo "At least one SSH key is required." >&2
        exit 1
      fi
      nixoa_tui_write_menu \
        "$hostname_value" \
        "$username_value" \
        "$timezone_value" \
        "$extras_value" \
        ssh_keys_value \
        system_packages_value \
        user_packages_value \
        services_value
      nixoa_tui_commit_paths "Remove SSH key from nixoa-menu" "$host_menu_relpath"
    else
      echo "SSH key not found."
    fi
    ;;
  toggle-extras)
    if [ "$extras_value" = "true" ]; then
      extras_value="false"
      commit_message="Disable extras from nixoa-menu"
    else
      extras_value="true"
      commit_message="Enable extras from nixoa-menu"
    fi
    nixoa_tui_write_menu \
      "$hostname_value" \
      "$username_value" \
      "$timezone_value" \
      "$extras_value" \
      ssh_keys_value \
      system_packages_value \
      user_packages_value \
      services_value
    nixoa_tui_commit_paths "$commit_message" "$host_menu_relpath"
    ;;
  add-system-package)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_token "package" "$1"
    if nixoa_tui_append_unique "$1" system_packages_value; then
      nixoa_tui_write_menu \
        "$hostname_value" \
        "$username_value" \
        "$timezone_value" \
        "$extras_value" \
        ssh_keys_value \
        system_packages_value \
        user_packages_value \
        services_value
      nixoa_tui_commit_paths "Add system package ${1} from nixoa-menu" "$host_menu_relpath"
    else
      echo "System package already present."
    fi
    ;;
  add-user-package)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_token "package" "$1"
    if nixoa_tui_append_unique "$1" user_packages_value; then
      nixoa_tui_write_menu \
        "$hostname_value" \
        "$username_value" \
        "$timezone_value" \
        "$extras_value" \
        ssh_keys_value \
        system_packages_value \
        user_packages_value \
        services_value
      nixoa_tui_commit_paths "Add user package ${1} from nixoa-menu" "$host_menu_relpath"
    else
      echo "User package already present."
    fi
    ;;
  add-service)
    [ $# -eq 1 ] || { usage >&2; exit 1; }
    nixoa_tui_validate_token "service" "$1"
    if nixoa_tui_append_unique "$1" services_value; then
      nixoa_tui_write_menu \
        "$hostname_value" \
        "$username_value" \
        "$timezone_value" \
        "$extras_value" \
        ssh_keys_value \
        system_packages_value \
        user_packages_value \
        services_value
      nixoa_tui_commit_paths "Enable service ${1} from nixoa-menu" "$host_menu_relpath"
    else
      echo "Service already present."
    fi
    ;;
  update-nixpkgs)
    update_input_and_prompt \
      "Update nixpkgs input from nixoa-menu" \
      nix flake lock --update-input nixpkgs
    ;;
  update-home-manager)
    update_input_and_prompt \
      "Update home-manager input from nixoa-menu" \
      nix flake lock --update-input home-manager
    ;;
  update-determinate)
    update_input_and_prompt \
      "Update determinate input from nixoa-menu" \
      nix flake lock --update-input determinate
    ;;
  update-xoa)
    current_xoa_rev="$(lock_rev_for xen-orchestra-ce)"
    current_xoa_url="$(lock_url_for xen-orchestra-ce)"
    if [ -z "$current_xoa_url" ]; then
      echo "Could not determine the xen-orchestra-ce source URL from core's flake input." >&2
      exit 1
    fi
    latest_tag_line="$(latest_xoa_tag "$(normalize_git_remote "$current_xoa_url")")"
    if [ -z "$latest_tag_line" ]; then
      echo "Could not determine the latest xen-orchestra-ce tag." >&2
      exit 1
    fi
    read -r latest_tag_name latest_tag_rev <<EOF
$latest_tag_line
EOF
    echo "Current locked xen-orchestra-ce revision: ${current_xoa_rev:-unknown}"
    echo "Latest upstream tag: ${latest_tag_name} @ ${latest_tag_rev}"
    if [ -n "$current_xoa_rev" ] && [ "$current_xoa_rev" = "$latest_tag_rev" ]; then
      echo "The locked xen-orchestra-ce input already matches the latest tagged commit."
    fi
    update_input_and_prompt \
      "Update xen-orchestra-ce input from nixoa-menu" \
      nix flake lock --update-input xen-orchestra-ce
    ;;
  update-all)
    update_input_and_prompt \
      "Update flake inputs from nixoa-menu" \
      nix flake update
    ;;
  cleanup-unmanaged-users)
    nixoa_run_as_root bash -lc "$(declare -f cleanup_unmanaged_users); cleanup_unmanaged_users $(printf '%q' "$username_value")"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
