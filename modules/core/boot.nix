# SPDX-License-Identifier: Apache-2.0
# Boot and bootloader configuration with systemd-boot as default

{
  config,
  pkgs,
  lib,
  vars,
  ...
}:

let
  inherit (lib)
    mkDefault
    mkIf
    ;
in
{
  config = {
    # ============================================================================
    # BOOTLOADER CONFIGURATION
    # ============================================================================

    # Systemd-boot configuration (default)
    boot.loader.systemd-boot.enable = mkDefault (vars.bootLoader == "systemd-boot");
    boot.loader.efi.canTouchEfiVariables = mkIf (
      vars.bootLoader == "systemd-boot"
    ) vars.efiCanTouchVariables;

    # GRUB configuration (alternative for BIOS/legacy boot)
    # Only defined when loader is set to "grub"
    boot.loader.grub = mkIf (vars.bootLoader == "grub") {
      enable = true;
      device = vars.grubDevice;
    };

    # ============================================================================
    # KERNEL & FILESYSTEM SUPPORT
    # ============================================================================

    # Ensure NFS client utilities and services are available in initrd
    boot.initrd.supportedFilesystems = [ "nfs" ];
    boot.initrd.kernelModules = [ "nfs" ];

    # Optional kernel parameters (useful for VMs and debugging)
    # Uncomment and customize as needed:
    # boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

    # ============================================================================
    # PERFORMANCE TUNING
    # ============================================================================
    # Enable Partition Growth of root partition at boot
    boot.growPartition = true;
  };
}
