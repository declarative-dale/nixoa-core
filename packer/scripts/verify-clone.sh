#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

assert_sshd_option() {
  local config=$1 option=$2 expected=$3 actual
  actual=$(awk -v option="$option" '$1 == option { print $2; exit }' <<<"$config")
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected sshd %s=%s, got %s.\n' \
      "$option" "$expected" "${actual:-<unset>}" >&2
    return 1
  fi
}

[[ "$(id -u)" -eq 0 ]] || {
  printf 'NiXOA clone verification must run as root.\n' >&2
  exit 1
}

cloud-init status --wait --long
test "$(cloud-id 2>/dev/null | tr '[:upper:]' '[:lower:]')" = nocloud

machine_id=$(</etc/machine-id)
[[ "$machine_id" =~ ^[0-9a-f]{32}$ ]]
for key_type in ed25519 rsa; do
  test -s "/etc/ssh/ssh_host_${key_type}_key"
  ssh-keygen -l -f "/etc/ssh/ssh_host_${key_type}_key.pub" >/dev/null
done

sshd_nixoa=$(sshd -T -C user=nixoa,host=localhost,addr=127.0.0.1)
sshd_root=$(sshd -T -C user=root,host=localhost,addr=127.0.0.1)
assert_sshd_option "$sshd_nixoa" passwordauthentication no
assert_sshd_option "$sshd_root" permitrootlogin no
test -s /home/nixoa/.ssh/authorized_keys

systemctl is-active --quiet \
  redis-xo.service \
  sshd.service \
  xen-guest-agent.service \
  xo-server.service
test "$(redis-cli -s /run/redis-xo/redis.sock --raw PING)" = PONG
curl --fail --silent --show-error --insecure https://127.0.0.1/ >/dev/null

printf 'NiXOA NoCloud clone verification passed.\n'
