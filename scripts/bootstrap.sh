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
  --branch NAME         Branch to clone or update. Defaults to beta.
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
  --first-switch        Run nxcli apply --first-install after setup.
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

repo_url="https://codeberg.org/NiXOA/core.git"
branch="beta"
repo_dir=""
repo_dir_explicit=0
enable_flakes=0
hostname_arg=""
username_arg=""
declare -a host_add_args=()

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

if [ -z "$repo_dir" ]; then
  default_bootstrap_user="${username_arg:-$NIXOA_DEFAULT_USERNAME}"
  repo_dir="$(nixoa_prompt_with_default "Repository path" "$(resolve_user_home "$default_bootstrap_user")/nixoa")"
fi

if [ "$enable_flakes" -eq 1 ]; then
  enable_flakes_now
fi

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
  mkdir -p "$repo_parent_dir"
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
