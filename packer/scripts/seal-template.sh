#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || {
  printf 'NiXOA template sealing must run as root.\n' >&2
  exit 1
}

repo=/home/nixoa/nixoa
test -d "$repo/.git"

canonical_module="$(mktemp "$repo/host/.packer-canonical.XXXXXX")"
cleanup() {
  rm -f -- "${canonical_module:-}"
}
trap cleanup EXIT HUP INT TERM

git -C "$repo" show HEAD:host/packer.nix >"$canonical_module"
chmod 0644 "$canonical_module"
mv -f "$canonical_module" "$repo/host/packer.nix"
canonical_module=

nixos-rebuild switch --flake "path:$repo#nixoa"

sshd_effective=$(sshd -T -C user=nixoa,host=localhost,addr=127.0.0.1)
test "$(awk '$1 == "passwordauthentication" { print $2; exit }' <<<"$sshd_effective")" = no
test "$(awk '$1 == "permitrootlogin" { print $2; exit }' <<<"$sshd_effective")" = no
case "$(getent shadow nixoa | cut -d: -f2)" in
  '!'*|'*'*) ;;
  *)
    printf 'The nixoa password was not locked while sealing.\n' >&2
    exit 1
    ;;
esac

git -C "$repo" add \
  host/hardware-configuration.nix \
  host/settings.nix
if ! git -C "$repo" diff --cached --quiet; then
  git -C "$repo" \
    -c user.name="NiXOA Packer" \
    -c user.email="packer@nixoa" \
    commit -m "Configure generated NiXOA template"
fi
test -z "$(git -C "$repo" status --short)"
chown -R nixoa:users "$repo"

cloud-init clean --logs --machine-id --seed
rm -f -- /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
rm -f -- /var/lib/systemd/random-seed

if [[ -s /etc/machine-id ]]; then
  grep -Fqx uninitialized /etc/machine-id
fi
test -z "$(find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*_key*' -print -quit)"

sync
printf 'NiXOA template sealed for NoCloud cloning.\n'
