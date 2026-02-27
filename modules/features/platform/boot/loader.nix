# SPDX-License-Identifier: Apache-2.0
# Boot loader selection
{
  lib,
  vars,
  ...
}:
{
  # Systemd-boot configuration (default)
  boot.loader.systemd-boot.enable = lib.mkDefault (vars.bootLoader == "systemd-boot");
  boot.loader.efi.canTouchEfiVariables = lib.mkIf (
    vars.bootLoader == "systemd-boot"
  ) vars.efiCanTouchVariables;

  # GRUB configuration (alternative for BIOS/legacy boot)
  boot.loader.grub = lib.mkIf (vars.bootLoader == "grub") {
    enable = true;
    device = vars.grubDevice;
  };
}
