#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || {
  printf 'NiXOA template verification must run as root.\n' >&2
  exit 1
}

report_error() {
  status=$?
  printf 'NiXOA template verification failed at line %s (status %s).\n' \
    "${BASH_LINENO[0]}" "$status" >&2
  exit "$status"
}
trap report_error ERR

assert_sshd_option() {
  local config=$1 option=$2 expected=$3 actual
  actual=$(awk -v option="$option" '$1 == option { print $2; exit }' <<<"$config")
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected sshd %s=%s, got %s.\n' \
      "$option" "$expected" "${actual:-<unset>}" >&2
    return 1
  fi
}

cloud_status=0
cloud-init status --wait --long || cloud_status=$?
case "$cloud_status" in
  0)
    ;;
  2)
    [[ "$(cloud-id 2>/dev/null | tr '[:upper:]' '[:lower:]')" == none ]]
    ;;
  *)
    exit "$cloud_status"
    ;;
esac

active_units=(
  cloud-config.service
  redis-xo.service
  sshd.service
  xen-guest-agent.service
  xo-server.service
)

deadline=$((SECONDS + 900))
while :; do
  inactive_units=()
  for unit in "${active_units[@]}"; do
    systemctl is-active --quiet "$unit" || inactive_units+=("$unit")
  done
  [[ "${#inactive_units[@]}" -eq 0 ]] && break
  if ((SECONDS >= deadline)); then
    printf 'Timed out waiting for services: %s\n' "${inactive_units[*]}" >&2
    systemctl --no-pager --full status "${inactive_units[@]}" || true
    exit 1
  fi
  sleep 2
done

systemctl is-enabled --quiet \
  cloud-init-local.service \
  redis-xo.service \
  sshd.service \
  xen-guest-agent.service \
  xo-server.service

test -d /home/nixoa/nixoa/.git
test -s /home/nixoa/nixoa/host/hardware-configuration.nix
grep -Fq 'networking.hostName = "nixoa";' \
  /home/nixoa/nixoa/host/settings.nix
grep -Fq 'PasswordAuthentication = lib.mkForce true;' \
  /home/nixoa/nixoa/host/packer.nix

sshd_nixoa=$(sshd -T -C user=nixoa,host=localhost,addr=127.0.0.1)
sshd_root=$(sshd -T -C user=root,host=localhost,addr=127.0.0.1)
assert_sshd_option "$sshd_root" permitrootlogin no
assert_sshd_option "$sshd_nixoa" passwordauthentication yes
assert_sshd_option "$sshd_nixoa" allowusers nixoa

test "$(redis-cli -s /run/redis-xo/redis.sock --raw PING)" = PONG
curl --fail --silent --show-error --insecure https://127.0.0.1/ >/dev/null
ss -lnt | grep -Eq '[:.]443[[:space:]]'

printf 'NiXOA template verification passed.\n'
