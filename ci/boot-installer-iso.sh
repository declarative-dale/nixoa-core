#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

iso=${1:?usage: boot-installer-iso.sh ISO}
[[ -s "$iso" ]] || {
  printf 'Installer ISO is missing: %s\n' "$iso" >&2
  exit 2
}

qemu_bin=${QEMU_BIN:-qemu-system-x86_64}
qemu_img_bin=${QEMU_IMG_BIN:-qemu-img}
boot_timeout=${BOOT_TIMEOUT:-5m}
log=${BOOT_LOG:-$(dirname "$iso")/qemu-boot.log}
disk=$(mktemp "${TMPDIR:-/tmp}/nixoa-boot.XXXXXX.qcow2")
trap 'rm -f -- "$disk"' EXIT

command -v "$qemu_bin" >/dev/null
command -v "$qemu_img_bin" >/dev/null
"$qemu_img_bin" create -q -f qcow2 "$disk" 24G

acceleration=(-accel "tcg,thread=multi")
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  acceleration=(-accel kvm)
fi

set +e
timeout --signal=TERM "$boot_timeout" \
  "$qemu_bin" \
    "${acceleration[@]}" \
    -machine q35 \
    -m 4096 \
    -smp 2 \
    -drive "file=${disk},if=virtio,format=qcow2" \
    -cdrom "$iso" \
    -boot d \
    -display none \
    -no-reboot \
    -chardev stdio,id=nixoa-console,signal=off \
    -device virtio-serial-pci \
    -device virtconsole,chardev=nixoa-console 2>&1 | tee "$log"
qemu_status=${PIPESTATUS[0]}
set -e

case "$qemu_status" in
  0|124|143) ;;
  *)
    printf 'QEMU failed with status %s\n' "$qemu_status" >&2
    exit "$qemu_status"
    ;;
esac

grep -Eqi 'nixoa-installer login:|Reached target .*Multi-User System|Started OpenSSH' "$log" || {
  printf 'The ISO did not reach the NiXOA installer login target.\n' >&2
  exit 1
}
