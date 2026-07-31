#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

readonly INSTALL_ROOT=/mnt
readonly DEFAULT_REPO_URL=https://codeberg.org/NiXOA/core.git
readonly DEFAULT_BRANCH=main
# shellcheck disable=SC2016
readonly PACKER_PASSWORD_HASH='$6$nixoapacker$cWN5T4ysgTquwJsxxFc/iF6rrl8MgYdDV6X4UV8t.MS5ATbQC4aYMsuXkKWsCH9AEBsGEzuEciGpFb6ylMgdU0'

usage() {
  cat <<'EOF'
Usage: install-nixoa [options]

Destructively install NiXOA on the single writable disk in this VM.

Options:
  --disk DEVICE        target disk; auto-detected when exactly one exists
  --repo-url URL       core repository URL
  --branch NAME        repository branch to install
  --operator-key FILE  required SSH public key file for nixoa
  --timezone ZONE      appliance timezone
  --git-name NAME      operator Git author name
  --git-email EMAIL    operator Git author email
  --yes                confirm destructive installation
  -h, --help           show this help
EOF
}

die() {
  printf 'install-nixoa: %s\n' "$1" >&2
  exit 1
}

require_argument() {
  [[ "$#" -ge 2 && -n "$2" ]] || die "$1 requires a value"
}

target_disk=
repo_url=$DEFAULT_REPO_URL
branch=$DEFAULT_BRANCH
operator_key_file=
timezone=America/Chicago
git_name="NiXOA Admin"
git_email=nixoa@nixoa
confirmed=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --disk)
      require_argument "$@"
      target_disk=$2
      shift 2
      ;;
    --repo-url)
      require_argument "$@"
      repo_url=$2
      shift 2
      ;;
    --branch)
      require_argument "$@"
      branch=$2
      shift 2
      ;;
    --operator-key)
      require_argument "$@"
      operator_key_file=$2
      shift 2
      ;;
    --timezone)
      require_argument "$@"
      timezone=$2
      shift 2
      ;;
    --git-name)
      require_argument "$@"
      git_name=$2
      shift 2
      ;;
    --git-email)
      require_argument "$@"
      git_email=$2
      shift 2
      ;;
    --yes)
      confirmed=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || die "must run as root"
[[ "$confirmed" -eq 1 ]] || die "refusing to erase a disk without --yes"
[[ -r "$operator_key_file" ]] || die "operator public key is required"

mapfile -t operator_keys < <(
  sed -nE '/^(ssh-|ecdsa-|sk-)[^[:space:]]+[[:space:]]+[^[:space:]]+/p' \
    "$operator_key_file"
)
[[ "${#operator_keys[@]}" -eq 1 ]] \
  || die "operator key file must contain exactly one valid public key"

if [[ -z "$target_disk" ]]; then
  mapfile -t install_disks < <(
    lsblk -dnpo NAME,TYPE,RO,RM |
      awk '$2 == "disk" && $3 == 0 && $4 == 0 { print $1 }'
  )
  [[ "${#install_disks[@]}" -eq 1 ]] \
    || die "expected one writable non-removable disk; pass --disk explicitly"
  target_disk=${install_disks[0]}
fi

[[ -b "$target_disk" ]] || die "target is not a block device: $target_disk"
[[ "$(lsblk -dnro TYPE "$target_disk")" == disk ]] \
  || die "target is not a whole disk: $target_disk"
[[ "$(lsblk -dnro RO "$target_disk")" == 0 ]] \
  || die "target disk is read-only: $target_disk"

case "$target_disk" in
  *[0-9])
    efi_partition="${target_disk}p1"
    root_partition="${target_disk}p2"
    ;;
  *)
    efi_partition="${target_disk}1"
    root_partition="${target_disk}2"
    ;;
esac

printf 'Installing NiXOA from %s (%s) onto %s\n' \
  "$repo_url" "$branch" "$target_disk"

wipefs --all --force "$target_disk"
sgdisk --zap-all "$target_disk"
sgdisk \
  --new=1:1MiB:+1GiB \
  --typecode=1:ef00 \
  --change-name=1:ESP \
  --new=2:0:0 \
  --typecode=2:8300 \
  --change-name=2:nixos \
  "$target_disk"
partprobe "$target_disk"
udevadm settle

mkfs.fat -F 32 -n ESP "$efi_partition"
mkfs.ext4 -F -L nixos "$root_partition"

sync
udevadm settle --timeout=30
mount_attempt=1
until mount -t ext4 "$root_partition" "$INSTALL_ROOT"; do
  if [[ "$mount_attempt" -ge 10 ]]; then
    printf 'Unable to mount the new root filesystem after %s attempts.\n' \
      "$mount_attempt" >&2
    lsblk -f "$target_disk" >&2 || true
    blkid -p "$root_partition" >&2 || true
    dumpe2fs -h "$root_partition" >&2 || true
    (dmesg || true) | tail -100 >&2
    die "new root filesystem did not become mountable"
  fi
  sleep 1
  udevadm settle --timeout=30
  ((mount_attempt += 1))
done
install -d -m 0755 "$INSTALL_ROOT/boot"
mount -o fmask=0077,dmask=0077 "$efi_partition" "$INSTALL_ROOT/boot"

repo_dir="$INSTALL_ROOT/home/nixoa/nixoa"
install -d -m 0755 "$(dirname "$repo_dir")"
git clone --branch "$branch" --single-branch "$repo_url" "$repo_dir"

export NIXOA_SYSTEM_ROOT="$repo_dir"
# The checkout does not exist on the live ISO when ShellCheck runs.
# shellcheck disable=SC1091
. "$repo_dir/scripts/lib/common.sh"

nixoa_write_host_settings \
  "$NIXOA_SETTINGS_FILE" \
  "/home/nixoa/nixoa" \
  "$timezone" \
  "26.05" \
  "$git_name" \
  "$git_email" \
  operator_keys

nixos-generate-config --root "$INSTALL_ROOT"
install -m 0644 \
  "$INSTALL_ROOT/etc/nixos/hardware-configuration.nix" \
  "$NIXOA_HARDWARE_FILE"

# The installed system keeps Packer's temporary password only long enough for
# the communicator to reconnect after the first reboot. The sealing
# provisioner restores the tracked empty module and switches once more.
packer_module_tmp="$(mktemp "$repo_dir/host/.packer.XXXXXX")"
trap 'rm -f -- "${packer_module_tmp:-}"' EXIT
cat >"$packer_module_tmp" <<EOF
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: {
  users.users.nixoa.hashedPassword = lib.mkForce "$PACKER_PASSWORD_HASH";
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;
}
EOF
chmod 0644 "$packer_module_tmp"
mv -f "$packer_module_tmp" "$repo_dir/host/packer.nix"
packer_module_tmp=

nixos-install \
  --root "$INSTALL_ROOT" \
  --flake "path:$repo_dir#nixoa" \
  --no-root-passwd

chown -R 1000:100 "$INSTALL_ROOT/home/nixoa"
sync
printf 'NiXOA installation complete; rebooting into the installed system.\n'
systemctl reboot
