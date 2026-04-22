#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bootstrap a fresh NiXOA checkout and create a concrete host directory

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --repo-dir PATH       Checkout directory. Defaults to the managed user's home plus /nixoa.
  --repo-url URL        Repository URL. Defaults to the unified core repository.
  --branch NAME         Branch to clone or update. Defaults to beta.
  --enable-flakes       Persist nix-command + flakes before validation.
  --hostname NAME       Hostname. Defaults to nixo-ce.
  --username NAME       Primary username. Defaults to nixoa.
  --git-name NAME       Git user.name override. Defaults to NiXOA Admin.
  --git-email EMAIL     Git user.email override. Defaults to nixoa@nixoa.
  --timezone ZONE       Time zone. Defaults to Europe/Paris.
  --state-version VER   State version. Defaults to 25.11.
  --profile NAME        Deployment profile: physical or vm. Defaults to physical.
  --ssh-key KEY         Add an SSH public key. Repeatable. At least one key is required.
  --skip-check          Skip nix flake check.
  --skip-hardware-copy  Do not copy /etc/nixos/hardware-configuration.nix.
  --first-switch        Run apply-config.sh --first-install after setup.
  --help                Show this help text.
EOF
}

nix_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
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

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local reply=""

  if [ ! -t 0 ]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  read -r -p "$prompt [$default_value]: " reply
  printf '%s\n' "${reply:-$default_value}"
}

prompt_with_default_note() {
  local prompt="$1"
  local default_value="$2"
  local note="$3"

  if [ ! -t 0 ]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  if [ -n "$note" ]; then
    printf '%s\n' "$note"
  fi

  prompt_with_default "$prompt" "$default_value"
}

prompt_required() {
  local prompt="$1"
  local reply=""

  if [ ! -t 0 ]; then
    echo "Error: $prompt is required. Pass it with --ssh-key in non-interactive mode." >&2
    exit 1
  fi

  while [ -z "$reply" ]; do
    read -r -p "$prompt: " reply
  done

  printf '%s\n' "$reply"
}

prompt_optional() {
  local prompt="$1"
  local reply=""

  if [ ! -t 0 ]; then
    printf '\n'
    return 0
  fi

  read -r -p "$prompt: " reply
  printf '%s\n' "$reply"
}

confirm_summary() {
  local reply=""

  if [ ! -t 0 ]; then
    return 0
  fi

  read -r -p "Proceed with these values [Y/n]: " reply
  case "$reply" in
    n|N|no|NO)
      echo "Bootstrap cancelled."
      exit 1
      ;;
  esac
}

validate_hostname() {
  local hostname="$1"

  if [ -z "$hostname" ]; then
    echo "Hostname must not be empty." >&2
    exit 1
  fi

  if [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
    echo "Hostname '$hostname' is invalid. Use letters, numbers, and dashes only." >&2
    exit 1
  fi
}

validate_username() {
  local username="$1"

  if [ -z "$username" ] || [[ "$username" =~ [[:space:]] ]]; then
    echo "Username must be non-empty and contain no whitespace." >&2
    exit 1
  fi
}

normalize_profile() {
  case "$1" in
    physical|vm)
      printf '%s\n' "$1"
      ;;
    *)
      echo "Invalid profile '$1'. Use 'physical' or 'vm'." >&2
      exit 1
      ;;
  esac
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
  local target_file
  local target_dir

  if flakes_are_enabled; then
    if [ -n "${NIX_CONFIG:-}" ]; then
      export NIX_CONFIG=$'experimental-features = nix-command flakes\n'"$NIX_CONFIG"
    else
      export NIX_CONFIG='experimental-features = nix-command flakes'
    fi
    echo "Flakes are already enabled."
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    target_file="/etc/nix/nix.conf"
    install -d -m 0755 /etc/nix
  else
    target_file="${XDG_CONFIG_HOME:-${HOME:-$repo_dir}/.config}/nix/nix.conf"
    target_dir="$(dirname "$target_file")"
    install -d -m 0755 "$target_dir"
  fi

  if [ -f "$target_file" ] \
    && grep -Eq '^[[:space:]]*experimental-features[[:space:]]*=.*nix-command' "$target_file" \
    && grep -Eq '^[[:space:]]*experimental-features[[:space:]]*=.*flakes' "$target_file"
  then
    echo "Flakes are already configured in $target_file"
    return 0
  fi

  {
    printf '\n# Added by NiXOA bootstrap\n'
    printf 'experimental-features = nix-command flakes\n'
  } >> "$target_file"

  if [ -n "${NIX_CONFIG:-}" ]; then
    export NIX_CONFIG=$'experimental-features = nix-command flakes\n'"$NIX_CONFIG"
  else
    export NIX_CONFIG='experimental-features = nix-command flakes'
  fi
  echo "Enabled flakes in $target_file"
}

run_as_root() {
  local sudo_bin

  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi

  if [ -x /run/wrappers/bin/sudo ]; then
    sudo_bin=/run/wrappers/bin/sudo
    "$sudo_bin" "$@"
    return $?
  fi

  if sudo_bin="$(command -v sudo 2>/dev/null)"; then
    "$sudo_bin" "$@"
    return $?
  fi

  echo "Error: root access is required for this bootstrap step, but sudo is not available." >&2
  exit 1
}

bootstrap_flake_check() {
  local flake_ref="path:$repo_dir"

  echo "Running nix flake check"
  run_as_root env \
    NIX_CONFIG='experimental-features = nix-command flakes' \
    nix \
    --accept-flake-config \
    --option extra-substituters "$xoa_cache_url" \
    --option extra-trusted-public-keys "$xoa_cache_key" \
    flake check \
    --no-write-lock-file \
    "$flake_ref"
}

write_host_settings() {
  local settings_file="$1"
  local boot_loader="systemd-boot"
  local efi_touch="true"

  if [ "$profile_arg" = "vm" ]; then
    boot_loader="none"
    efi_touch="false"
  fi

  {
    echo "# SPDX-License-Identifier: Apache-2.0"
    echo "# Generated by scripts/bootstrap.sh"
    echo "{ ... }:"
    echo "{"
    echo "  hostSystem = \"x86_64-linux\";"
    echo "  hostname = $(nix_quote "$hostname_arg");"
    echo "  deploymentProfile = $(nix_quote "$profile_arg");"
    echo "  repoDir = $(nix_quote "$repo_dir");"
    echo ""
    echo "  timezone = $(nix_quote "$timezone_arg");"
    echo "  stateVersion = $(nix_quote "$state_version_arg");"
    echo ""
    echo "  username = $(nix_quote "$username_arg");"
    echo "  gitName = $(nix_quote "$git_name_arg");"
    echo "  gitEmail = $(nix_quote "$git_email_arg");"
    echo "  sshKeys = ["
    for ssh_key in "${ssh_keys[@]}"; do
      echo "    $(nix_quote "$ssh_key")"
    done
    echo "  ];"
    echo ""
    echo "  bootLoader = $(nix_quote "$boot_loader");"
    echo "  efiCanTouchVariables = ${efi_touch};"
    echo "  grubDevice = \"\";"
    echo ""
    echo "  allowedTCPPorts = [ 80 443 ];"
    echo "  allowedUDPPorts = [ ];"
    echo ""
    echo "  enableExtras = false;"
    echo "  enableXO = true;"
    echo "  enableXenGuest = true;"
    echo ""
    echo "  systemPackages = [ ];"
    echo "  userPackages = [ ];"
    echo ""
    echo "  xoConfigFile = ../../config.nixoa.toml;"
    echo "  xoHttpHost = \"0.0.0.0\";"
    echo "  enableTLS = true;"
    echo "  enableAutoCert = true;"
    echo ""
    echo "  enableNFS = true;"
    echo "  enableCIFS = true;"
    echo "  enableVHD = true;"
    echo "  mountsDir = \"/var/lib/xo/mounts\";"
    echo "  sudoNoPassword = true;"
    echo "}"
  } > "$settings_file"
}

repo_url="https://codeberg.org/NiXOA/core.git"
branch="beta"
repo_dir=""
repo_dir_explicit=0
default_hostname="nixo-ce"
default_username="nixoa"
default_git_name="NiXOA Admin"
default_git_email="nixoa@nixoa"
default_timezone="Europe/Paris"
default_state_version="25.11"
default_profile="physical"
enable_flakes=0
skip_check=0
skip_hardware_copy=0
first_switch=0
xoa_cache_url="https://xen-orchestra-ce.cachix.org"
xoa_cache_key="xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
launch_user="$(id -un)"
launch_group="$(id -gn)"
managed_home_dir=""
managed_user_exists=0
hostname_arg=""
username_arg=""
git_name_arg=""
git_email_arg=""
timezone_arg=""
state_version_arg=""
profile_arg=""
declare -a ssh_keys=()

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
    --profile)
      profile_arg="$2"
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
    --skip-hardware-copy)
      skip_hardware_copy=1
      shift
      ;;
    --first-switch)
      first_switch=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$hostname_arg" ]; then
  hostname_arg="$(prompt_with_default "Hostname" "$default_hostname")"
fi
validate_hostname "$hostname_arg"

if [ -z "$username_arg" ]; then
  username_arg="$(prompt_with_default "Username" "$default_username")"
fi
validate_username "$username_arg"

if getent passwd "$username_arg" >/dev/null 2>&1; then
  managed_user_exists=1
fi

managed_home_dir="$(resolve_user_home "$username_arg")"

if [ "$repo_dir_explicit" -eq 0 ]; then
  repo_dir="${managed_home_dir}/nixoa"
  repo_dir="$(prompt_with_default "Repository path" "$repo_dir")"
fi

if [ -z "$git_name_arg" ]; then
  git_name_arg="$(prompt_with_default "Git user.name" "$default_git_name")"
fi

if [ -z "$git_email_arg" ]; then
  git_email_arg="$(
    prompt_with_default_note \
      "Git user.email" \
      "$default_git_email" \
      "If this Git config will only be saved locally, the email address does not need to be a real inbox."
  )"
fi

if [ -z "$timezone_arg" ]; then
  timezone_arg="$(prompt_with_default "Time zone" "$default_timezone")"
fi

if [ -z "$state_version_arg" ]; then
  state_version_arg="$(prompt_with_default "State version" "$default_state_version")"
fi

if [ -z "$profile_arg" ]; then
  profile_arg="$(prompt_with_default "Deployment profile (physical|vm)" "$default_profile")"
fi
profile_arg="$(normalize_profile "$profile_arg")"

if [ "${#ssh_keys[@]}" -eq 0 ]; then
  ssh_keys+=( "$(prompt_required "SSH public key")" )
fi

while true; do
  extra_ssh_key="$(prompt_optional "Additional SSH public key [leave blank to finish]")"
  [ -n "$extra_ssh_key" ] || break
  ssh_keys+=("$extra_ssh_key")
done

if [ "$enable_flakes" -eq 1 ]; then
  enable_flakes_now
fi

echo ""
echo "Bootstrap summary:"
echo "  Repository URL: $repo_url"
echo "  Repository path: $repo_dir"
echo "  Branch: $branch"
echo "  Host directory: hosts/$hostname_arg"
echo "  Hostname: $hostname_arg"
echo "  Username: $username_arg"
echo "  Time zone: $timezone_arg"
echo "  State version: $state_version_arg"
echo "  Deployment profile: $profile_arg"
echo "  SSH keys: ${#ssh_keys[@]}"
confirm_summary

if [ -d "$repo_dir/.git" ]; then
  if [ ! -w "$repo_dir" ]; then
    echo "Error: $repo_dir is not writable by $launch_user. Run bootstrap as $username_arg or pass --repo-dir to a writable location." >&2
    exit 1
  fi
  echo "Updating existing checkout in $repo_dir"
  git -C "$repo_dir" fetch origin "$branch"
  git -C "$repo_dir" checkout "$branch"
  git -C "$repo_dir" pull --ff-only origin "$branch"
else
  repo_parent_dir="$(dirname "$repo_dir")"
  if [ -d "$repo_parent_dir" ]; then
    if [ ! -w "$repo_parent_dir" ]; then
      if [ "$repo_dir_explicit" -eq 0 ] && [ "$managed_user_exists" -eq 0 ]; then
        run_as_root install -d -m 0755 -o "$launch_user" -g "$launch_group" "$repo_parent_dir"
      else
        echo "Error: $repo_parent_dir is not writable by $launch_user. Pass --repo-dir to a writable location or run bootstrap as the target user." >&2
        exit 1
      fi
    fi
  elif mkdir -p "$repo_parent_dir" 2>/dev/null; then
    :
  elif [ "$repo_dir_explicit" -eq 0 ] && [ "$managed_user_exists" -eq 0 ]; then
    run_as_root install -d -m 0755 -o "$launch_user" -g "$launch_group" "$repo_parent_dir"
  else
    echo "Error: $repo_parent_dir is not writable by $launch_user. Pass --repo-dir to a writable location or run bootstrap as the target user." >&2
    exit 1
  fi
  echo "Cloning $repo_url into $repo_dir"
  git clone --branch "$branch" "$repo_url" "$repo_dir"
fi

template_dir="$repo_dir/hosts/_template"
host_dir="$repo_dir/hosts/$hostname_arg"
settings_file="$host_dir/_ctx/settings.nix"
hardware_file="$host_dir/_nixos/hardware-configuration.nix"

if [ ! -d "$template_dir" ]; then
  echo "Error: host template not found at $template_dir" >&2
  exit 1
fi

if [ -e "$host_dir" ]; then
  echo "Error: host directory $host_dir already exists." >&2
  exit 1
fi

cp -r "$template_dir" "$host_dir"
echo "Created $host_dir from hosts/_template"

write_host_settings "$settings_file"
echo "Wrote $settings_file"

if [ "$skip_hardware_copy" -eq 0 ] && [ -f /etc/nixos/hardware-configuration.nix ]; then
  install -m 0644 /etc/nixos/hardware-configuration.nix "$hardware_file"
  echo "Copied hardware-configuration.nix to $hardware_file"
fi

git -C "$repo_dir" add "hosts/$hostname_arg"
echo "Staged hosts/$hostname_arg so flake evaluation includes the new host"

if [ "$skip_check" -eq 0 ]; then
  bootstrap_flake_check
fi

if [ "$first_switch" -eq 1 ]; then
  echo "Running first switch for ${hostname_arg}"
  "$repo_dir/scripts/apply-config.sh" --hostname "$hostname_arg" --first-install
fi

echo ""
echo "Bootstrap complete."
echo "Repository: $repo_dir"
echo "Configured host: $hostname_arg"
echo "Configured user: $username_arg"
echo "Next steps:"
echo "  1. Review $repo_dir/hosts/$hostname_arg/_ctx/settings.nix."
echo "  2. Run $repo_dir/scripts/show-diff.sh"
if [ "$first_switch" -eq 1 ]; then
  echo "  3. The initial apply already ran during bootstrap."
  echo "  4. Future applies can use: nh os switch $repo_dir#nixosConfigurations.$hostname_arg"
else
  echo "  3. Run $repo_dir/scripts/apply-config.sh --hostname $hostname_arg"
fi
