#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bootstrap a NiXOA checkout, then hand off to nxcli host add

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --repo-dir PATH       Checkout directory. Defaults to the managed user's home plus /nixoa.
  --repo-url URL        Repository URL. Defaults to the unified core repository.
  --branch NAME         Optional branch override. Defaults to the current branch of the
                        checkout running bootstrap.
  --enable-flakes       Persist nix-command + flakes before validation.
  --hostname NAME       Hostname to create with nxcli host add.
  --username NAME       Primary username passed through to nxcli host add.
  --git-name NAME       Git user.name override passed through to nxcli host add.
  --git-email EMAIL     Git user.email override passed through to nxcli host add.
  --timezone ZONE       Time zone passed through to nxcli host add.
  --state-version VER   State version passed through to nxcli host add.
  --profile NAME        Deployment profile: physical or vm.
  --ssh-key KEY         Add an SSH public key. Repeatable.
  --skip-check          Skip nix flake check after host creation.
  --skip-hardware-copy  Do not copy /etc/nixos/hardware-configuration.nix.
  --first-switch        Run the first switch after setup without prompting.
  --help                Show this help text.
EOF
}

resolve_user_home() {
  local username="$1"
  local passwd_entry=""

  passwd_entry="$(getent passwd "$username" 2>/dev/null || true)"
  if [ -n "$passwd_entry" ]; then
    printf '%s\n' "$passwd_entry" | cut -d: -f6
    return 0
  fi

  printf '/home/%s\n' "$username"
}

bootstrap_operator_user() {
  if [ "$(id -u)" -eq 0 ] && nixoa_user_exists "${SUDO_USER:-}"; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi

  id -un
}

prepare_repo_checkout_parent() {
  local repo_path="$1"
  local target_user="$2"
  local repo_parent_dir=""
  local repo_dir=""
  local target_home=""
  local operator_user=""
  local parent_exists=0
  local repo_dir_exists=0

  repo_parent_dir="$(dirname "$repo_path")"
  repo_dir="$repo_path"
  target_home="$(resolve_user_home "$target_user")"
  operator_user="$(bootstrap_operator_user)"

  if [ -d "$repo_parent_dir" ] && [ -w "$repo_parent_dir" ]; then
    :
  else
    if [ -d "$repo_parent_dir" ]; then
      parent_exists=1
    fi

    if [ "$parent_exists" -eq 0 ] && mkdir -p "$repo_parent_dir" 2>/dev/null && [ -w "$repo_parent_dir" ]; then
      :
    else
      nixoa_print_info "Preparing checkout parent $repo_parent_dir with root privileges"
      nixoa_run_as_root install -d -m 0755 "$repo_parent_dir"

      if [ "$operator_user" != "root" ] && [[ "$repo_parent_dir" == "$target_home" || "$repo_parent_dir" == "$target_home/"* ]]; then
        nixoa_run_as_root chown "$operator_user:users" "$repo_parent_dir"
        nixoa_print_info "Temporarily assigned $repo_parent_dir to $operator_user for bootstrap. The first switch will hand it to $target_user."
      fi
    fi
  fi

  if [ "$(id -u)" -ne 0 ] && [ ! -w "$repo_parent_dir" ]; then
    nixoa_print_error "Checkout parent $repo_parent_dir is not writable by $operator_user."
    nixoa_print_error "Choose a writable --repo-dir or rerun bootstrap with sudo so it can prepare the path."
    exit 1
  fi

  if [ -d "$repo_dir" ]; then
    repo_dir_exists=1
  fi

  if [ "$repo_dir_exists" -eq 1 ] && [ ! -d "$repo_dir/.git" ] && [ "$operator_user" != "root" ] && [ ! -w "$repo_dir" ] && [[ "$repo_dir" == "$target_home" || "$repo_dir" == "$target_home/"* ]]; then
    nixoa_print_info "Repairing bootstrap checkout directory ownership for $repo_dir"
    nixoa_run_as_root chown "$operator_user:users" "$repo_dir"
  fi

  if [ "$repo_dir_exists" -eq 1 ] && [ ! -d "$repo_dir/.git" ]; then
    if [ ! -w "$repo_dir" ]; then
      nixoa_print_error "Checkout directory $repo_dir exists but is not writable by $operator_user."
      nixoa_print_error "Remove it, choose a different --repo-dir, or rerun bootstrap with sudo so it can repair the path."
      exit 1
    fi

    if find "$repo_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
      nixoa_print_error "Checkout directory $repo_dir already exists and is not an existing git checkout."
      nixoa_print_error "Remove it or choose a different --repo-dir before running bootstrap again."
      exit 1
    fi
  elif [ -e "$repo_dir" ] && [ ! -d "$repo_dir" ]; then
    nixoa_print_error "Checkout path $repo_dir exists but is not a directory."
    exit 1
  fi
}

flakes_are_enabled() {
  if nix show-config experimental-features >/dev/null 2>&1; then
    local features
    features="$(nix show-config experimental-features 2>/dev/null || true)"
    printf '%s' "$features" | grep -Eq 'nix-command' \
      && printf '%s' "$features" | grep -Eq 'flakes'
    return $?
  fi

  return 1
}

enable_flakes_now() {
  local target_file=""
  local target_dir=""

  if flakes_are_enabled; then
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    target_file="/etc/nix/nix.conf"
    install -d -m 0755 /etc/nix
  else
    target_file="${XDG_CONFIG_HOME:-${HOME:-$PWD}/.config}/nix/nix.conf"
    target_dir="$(dirname "$target_file")"
    install -d -m 0755 "$target_dir"
  fi

  if [ -f "$target_file" ] \
    && grep -Eq '^[[:space:]]*experimental-features[[:space:]]*=.*nix-command' "$target_file" \
    && grep -Eq '^[[:space:]]*experimental-features[[:space:]]*=.*flakes' "$target_file"
  then
    return 0
  fi

  {
    printf '\n# Added by NiXOA bootstrap\n'
    printf 'experimental-features = nix-command flakes\n'
  } >> "$target_file"
}

nix_conf_read_setting() {
  local file="$1"
  local key="$2"

  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\\1/p" "$file" | tail -n 1
}

nix_conf_ensure_tokens() {
  local file="$1"
  local key="$2"
  shift 2

  local current=""
  local merged=()
  local token=""
  local existing=""
  local found=0
  local merged_line=""
  local temp_file=""
  local file_mode="0644"

  current="$(nix_conf_read_setting "$file" "$key" || true)"

  if [ -n "$current" ]; then
    for token in $current; do
      found=0
      for existing in "${merged[@]}"; do
        if [ "$existing" = "$token" ]; then
          found=1
          break
        fi
      done
      if [ "$found" -eq 0 ]; then
        merged+=("$token")
      fi
    done
  fi

  for token in "$@"; do
    found=0
    for existing in "${merged[@]}"; do
      if [ "$existing" = "$token" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      merged+=("$token")
    fi
  done

  merged_line="${key} = ${merged[*]}"
  if [ "$current" = "${merged[*]}" ]; then
    return 0
  fi

  temp_file="$(mktemp)"
  if [ -f "$file" ]; then
    awk -v key="$key" -v line="$merged_line" '
      $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        if (!replaced) {
          print line
          replaced = 1
        }
        next
      }
      { print }
      END {
        if (!replaced) {
          print line
        }
      }
    ' "$file" > "$temp_file"
    file_mode="$(stat -c '%a' "$file" 2>/dev/null || printf '0644')"
  else
    printf '%s\n' "$merged_line" > "$temp_file"
  fi

  nixoa_run_as_root install -m "$file_mode" "$temp_file" "$file"
  rm -f "$temp_file"
}

restart_nix_daemon_if_needed() {
  local systemctl_bin=""
  local service_present=0
  local socket_present=0

  systemctl_bin="$(command -v systemctl 2>/dev/null || true)"
  [ -n "$systemctl_bin" ] || return 0

  nixoa_print_info "Restarting nix-daemon so the new trusted cache settings take effect"

  if nixoa_run_as_root "$systemctl_bin" cat nix-daemon.service >/dev/null 2>&1; then
    service_present=1
  fi

  if nixoa_run_as_root "$systemctl_bin" cat nix-daemon.socket >/dev/null 2>&1; then
    socket_present=1
  fi

  if [ "$service_present" -eq 1 ]; then
    nixoa_run_as_root "$systemctl_bin" restart nix-daemon.service
  fi

  if [ "$socket_present" -eq 1 ]; then
    nixoa_run_as_root "$systemctl_bin" restart nix-daemon.socket
  fi
}

prepare_first_switch_nix_access() {
  local operator_user="$1"
  local target_user="$2"
  local nix_conf="/etc/nix/nix.conf"
  local before_trusted_users=""
  local before_substituters=""
  local before_keys=""
  local after_trusted_users=""
  local after_substituters=""
  local after_keys=""
  local users_to_trust=(
    root
    @wheel
  )

  if [ -n "$operator_user" ]; then
    users_to_trust+=("$operator_user")
  fi

  if [ -n "$target_user" ] && [ "$target_user" != "$operator_user" ]; then
    users_to_trust+=("$target_user")
  fi

  nixoa_print_info "Preparing trusted Nix cache settings for the initial switch"
  nixoa_run_as_root install -d -m 0755 /etc/nix
  before_trusted_users="$(nix_conf_read_setting "$nix_conf" trusted-users || true)"
  before_substituters="$(nix_conf_read_setting "$nix_conf" extra-substituters || true)"
  before_keys="$(nix_conf_read_setting "$nix_conf" extra-trusted-public-keys || true)"
  nix_conf_ensure_tokens "$nix_conf" trusted-users "${users_to_trust[@]}"
  nix_conf_ensure_tokens "$nix_conf" extra-substituters \
    "$NIXOA_DETERMINATE_SUBSTITUTER" \
    "$NIXOA_XO_SUBSTITUTER"
  nix_conf_ensure_tokens "$nix_conf" extra-trusted-public-keys \
    "$NIXOA_DETERMINATE_PUBLIC_KEY" \
    "$NIXOA_XO_PUBLIC_KEY"
  after_trusted_users="$(nix_conf_read_setting "$nix_conf" trusted-users || true)"
  after_substituters="$(nix_conf_read_setting "$nix_conf" extra-substituters || true)"
  after_keys="$(nix_conf_read_setting "$nix_conf" extra-trusted-public-keys || true)"

  if [ "$before_trusted_users" != "$after_trusted_users" ] \
    || [ "$before_substituters" != "$after_substituters" ] \
    || [ "$before_keys" != "$after_keys" ]
  then
    restart_nix_daemon_if_needed
  fi
}

repo_url="https://codeberg.org/NiXOA/core.git"
branch=""
repo_dir=""
repo_dir_explicit=0
enable_flakes=0
hostname_arg=""
username_arg=""
username_arg_explicit=0
first_switch_requested=0
declare -a host_add_args=()
host_add_args+=(--no-nom)

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir)
      repo_dir="$2"
      repo_dir_explicit=1
      shift 2
      ;;
    --repo-url)
      repo_url="$2"
      shift 2
      ;;
    --branch)
      branch="$2"
      shift 2
      ;;
    --enable-flakes)
      enable_flakes=1
      shift
      ;;
    --hostname)
      hostname_arg="$2"
      shift 2
      ;;
    --username)
      username_arg="$2"
      username_arg_explicit=1
      host_add_args+=(--username "$2")
      shift 2
      ;;
    --git-name)
      host_add_args+=(--git-name "$2")
      shift 2
      ;;
    --git-email)
      host_add_args+=(--git-email "$2")
      shift 2
      ;;
    --timezone)
      host_add_args+=(--timezone "$2")
      shift 2
      ;;
    --state-version)
      host_add_args+=(--state-version "$2")
      shift 2
      ;;
    --profile)
      host_add_args+=(--profile "$2")
      shift 2
      ;;
    --ssh-key)
      host_add_args+=(--ssh-key "$2")
      shift 2
      ;;
    --skip-check)
      host_add_args+=(--skip-check)
      shift
      ;;
    --skip-hardware-copy)
      host_add_args+=(--skip-hardware-copy)
      shift
      ;;
    --first-switch)
      host_add_args+=(--first-switch)
      first_switch_requested=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      nixoa_print_error "Unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$username_arg" ] && [ -t 0 ]; then
  username_arg="$(nixoa_prompt_with_default "Username" "$NIXOA_DEFAULT_USERNAME")"
  nixoa_validate_username "$username_arg"
fi

if [ "$username_arg_explicit" -eq 0 ] && [ -n "$username_arg" ]; then
  host_add_args+=(--username "$username_arg")
fi

if [ -z "$repo_dir" ]; then
  default_bootstrap_user="${username_arg:-$NIXOA_DEFAULT_USERNAME}"
  repo_dir="$(nixoa_prompt_with_default "Repository path" "$(resolve_user_home "$default_bootstrap_user")/nixoa")"
fi

if [ -z "$branch" ]; then
  branch="$(git -C "$(nixoa_system_root)" branch --show-current 2>/dev/null || true)"
fi

if [ -z "$branch" ]; then
  nixoa_print_error "Bootstrap must run from a named branch checkout or receive --branch explicitly."
  exit 1
fi

if [ "$enable_flakes" -eq 1 ]; then
  enable_flakes_now
fi

bootstrap_target_user="${username_arg:-$NIXOA_DEFAULT_USERNAME}"
bootstrap_operator="${SUDO_USER:-$(bootstrap_operator_user)}"

if [ "$first_switch_requested" -eq 1 ]; then
  prepare_first_switch_nix_access "$bootstrap_operator" "$bootstrap_target_user"
fi

prepare_repo_checkout_parent "$repo_dir" "$bootstrap_target_user"

if [ -d "$repo_dir/.git" ]; then
  if [ -n "$(git -C "$repo_dir" status --short 2>/dev/null || true)" ]; then
    nixoa_print_error "Existing checkout at $repo_dir is dirty. Clean it before running bootstrap."
    exit 1
  fi

  nixoa_print_info "Updating existing checkout in $repo_dir"
  git -C "$repo_dir" fetch origin "$branch"
  git -C "$repo_dir" checkout "$branch"
  git -C "$repo_dir" pull --ff-only origin "$branch"
else
  repo_parent_dir="$(dirname "$repo_dir")"
  nixoa_print_info "Cloning $repo_url into $repo_dir"
  git clone --branch "$branch" "$repo_url" "$repo_dir"
fi

bootstrap_cmd=("$repo_dir/scripts/nxcli.sh" host add)
if [ -n "$hostname_arg" ]; then
  bootstrap_cmd+=("$hostname_arg")
fi
bootstrap_cmd+=("${host_add_args[@]}")

printf 'Running:'
printf ' %q' "${bootstrap_cmd[@]}"
printf '\n'

"${bootstrap_cmd[@]}"
