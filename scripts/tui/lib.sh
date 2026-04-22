#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

TUI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TUI_LIB_DIR/../lib/common.sh"

nixoa_tui_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

nixoa_tui_has_key() {
  local key="$1"
  local file="$2"
  [ -f "$file" ] && grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file"
}

nixoa_tui_read_string_file() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;.*$/\\1/p" "$file" | tail -n 1
}

nixoa_tui_read_bool_file() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*;.*$/\\1/p" "$file" | tail -n 1
}

nixoa_tui_read_list_file() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 0
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=[[:space:]]*\\[" {
      in_list = 1
      next
    }
    in_list && $0 ~ /^[[:space:]]*\];/ {
      exit
    }
    in_list {
      if (match($0, /"([^"]+)"/, parts)) {
        print parts[1]
      }
    }
  ' "$file"
}

nixoa_tui_first_string() {
  local key="$1"
  shift
  local file
  local value

  for file in "$@"; do
    value="$(nixoa_tui_read_string_file "$key" "$file")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

nixoa_tui_first_bool() {
  local key="$1"
  shift
  local file
  local value

  for file in "$@"; do
    value="$(nixoa_tui_read_bool_file "$key" "$file")"
    if [ "$value" = "true" ] || [ "$value" = "false" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

nixoa_tui_hostname() {
  nixoa_tui_first_string hostname "$(nixoa_host_menu_file)" "$(nixoa_host_settings_file)" \
    || printf '%s\n' "$NIXOA_DEFAULT_HOSTNAME"
}

nixoa_tui_username() {
  nixoa_tui_first_string username "$(nixoa_host_menu_file)" "$(nixoa_host_settings_file)" \
    || printf '%s\n' "$NIXOA_DEFAULT_USERNAME"
}

nixoa_tui_timezone() {
  nixoa_tui_first_string timezone "$(nixoa_host_menu_file)" "$(nixoa_host_settings_file)" \
    || printf '%s\n' "$NIXOA_DEFAULT_TIMEZONE"
}

nixoa_tui_enable_extras() {
  nixoa_tui_first_bool enableExtras "$(nixoa_host_menu_file)" "$(nixoa_host_settings_file)" || printf '%s\n' false
}

nixoa_tui_ssh_keys() {
  local file

  for file in "$(nixoa_host_menu_file)" "$(nixoa_host_settings_file)"; do
    if nixoa_tui_has_key sshKeys "$file"; then
      nixoa_tui_read_list_file sshKeys "$file"
      return 0
    fi
  done
}

nixoa_tui_extra_system_packages() {
  nixoa_tui_read_list_file extraSystemPackages "$(nixoa_host_menu_file)"
}

nixoa_tui_extra_user_packages() {
  nixoa_tui_read_list_file extraUserPackages "$(nixoa_host_menu_file)"
}

nixoa_tui_enabled_services() {
  nixoa_tui_read_list_file enabledServices "$(nixoa_host_menu_file)"
}

nixoa_tui_dirty_count() {
  git -C "$NIXOA_SYSTEM_ROOT" status --short -- "${NIXOA_TRACKED_PATHS[@]}" | wc -l | tr -d ' '
}

nixoa_tui_write_menu() {
  local hostname="$1"
  local username="$2"
  local timezone="$3"
  local extras="$4"
  local -n ssh_keys_ref="$5"
  local -n system_packages_ref="$6"
  local -n user_packages_ref="$7"
  local -n services_ref="$8"
  local menu_file

  menu_file="$(nixoa_host_menu_file)"

  {
    echo "# SPDX-License-Identifier: Apache-2.0"
    echo "# Managed by nixoa-menu"
    echo "{ ... }:"
    echo "{"
    echo "  hostname = $(nixoa_tui_quote "$hostname");"
    echo "  username = $(nixoa_tui_quote "$username");"
    echo "  timezone = $(nixoa_tui_quote "$timezone");"
    echo ""
    echo "  sshKeys = ["
    for key in "${ssh_keys_ref[@]}"; do
      echo "    $(nixoa_tui_quote "$key")"
    done
    echo "  ];"
    echo ""
    echo "  enableExtras = ${extras};"
    echo ""
    echo "  extraSystemPackages = ["
    for package_name in "${system_packages_ref[@]}"; do
      echo "    $(nixoa_tui_quote "$package_name")"
    done
    echo "  ];"
    echo ""
    echo "  extraUserPackages = ["
    for package_name in "${user_packages_ref[@]}"; do
      echo "    $(nixoa_tui_quote "$package_name")"
    done
    echo "  ];"
    echo ""
    echo "  enabledServices = ["
    for service_name in "${services_ref[@]}"; do
      echo "    $(nixoa_tui_quote "$service_name")"
    done
    echo "  ];"
    echo "}"
  } > "$menu_file"
}

nixoa_tui_append_unique() {
  local value="$1"
  shift
  local -n items_ref="$1"
  local item

  for item in "${items_ref[@]}"; do
    if [ "$item" = "$value" ]; then
      return 1
    fi
  done

  items_ref+=("$value")
  return 0
}

nixoa_tui_validate_token() {
  local label="$1"
  local value="$2"

  if [[ -z "$value" || "$value" =~ [[:space:]] ]]; then
    echo "Invalid ${label}: '${value}'" >&2
    echo "${label} values must be non-empty and contain no whitespace." >&2
    exit 1
  fi
}

nixoa_tui_validate_ssh_key() {
  local value="$1"

  if [[ "$value" != ssh-* && "$value" != ecdsa-* && "$value" != sk-* ]]; then
    echo "SSH key must be a public key line starting with ssh-, ecdsa-, or sk-." >&2
    exit 1
  fi
}

nixoa_tui_remove_value() {
  local value="$1"
  shift
  local -n items_ref="$1"
  local filtered=()
  local found=1
  local item

  for item in "${items_ref[@]}"; do
    if [ "$item" = "$value" ]; then
      found=0
      continue
    fi
    filtered+=("$item")
  done

  items_ref=("${filtered[@]}")
  return "$found"
}

nixoa_tui_commit_paths() {
  local message="$1"
  shift

  if [ -z "$(git -C "$NIXOA_SYSTEM_ROOT" status --short -- "$@")" ]; then
    echo "No tracked changes to commit."
    return 0
  fi

  git -C "$NIXOA_SYSTEM_ROOT" add -- "$@"
  git -C "$NIXOA_SYSTEM_ROOT" commit -m "$message"
}
