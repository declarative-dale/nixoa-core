# SPDX-License-Identifier: Apache-2.0
# Host boot loader policy
{
  lib,
  context,
  ...
}:
{
  boot.loader.systemd-boot.enable = context.bootLoader == "systemd-boot";
  boot.loader.efi.canTouchEfiVariables = lib.mkIf (
    context.bootLoader == "systemd-boot"
  ) context.efiCanTouchVariables;

  boot.loader.grub = lib.mkIf (context.bootLoader == "grub") {
    enable = true;
    device = context.grubDevice;
  };
}
