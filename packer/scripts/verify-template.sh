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

assert_sshd_directive() {
  local config=$1 directive=$2 expected=$3 actual
  actual=$(awk -v directive="$directive" '
    tolower($1) == "match" { exit }
    tolower($1) == tolower(directive) {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      print
      exit
    }
  ' "$config")
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected global sshd directive %s=%s, got %s.\n' \
      "$directive" "$expected" "${actual:-<unset>}" >&2
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

sshd -t
assert_sshd_directive /etc/ssh/sshd_config PermitRootLogin no
assert_sshd_directive /etc/ssh/sshd_config PasswordAuthentication yes
assert_sshd_directive /etc/ssh/sshd_config AllowUsers nixoa

test "$(redis-cli -s /run/redis-xo/redis.sock --raw PING)" = PONG
curl --fail --silent --show-error --insecure https://127.0.0.1/ >/dev/null
ss -lnt | grep -Eq '[:.]443[[:space:]]'

printf 'NiXOA template verification passed.\n'
