# SPDX-License-Identifier: Apache-2.0
# VM guest profile for a real installed appliance running inside a hypervisor
{ lib, ... }:
{
  # The VM deployment profile is for an already-installed guest, not for
  # qemu-vm.nix build-vm artifacts. Keep boot loader management off so the
  # first switch does not try to replace whatever the base image already uses.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
}
