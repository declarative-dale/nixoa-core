# SPDX-License-Identifier: Apache-2.0
# VM profile for building the appliance as a QEMU VM
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  services.qemuGuest.enable = lib.mkDefault true;

  virtualisation = {
    graphics = false;
    memorySize = 4096;
    cores = 4;
  };
}
