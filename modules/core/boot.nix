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

    # Swappiness (lower = less swap usage, 10 is reasonable for VMs with adequate RAM)
    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 10;

      # Network tuning for XO
      "net.core.somaxconn" = 1024;
      "net.ipv4.tcp_max_syn_backlog" = 2048;

      # File handle limits
      "fs.file-max" = 1000000;
      "fs.inotify.max_user_instances" = 8192;
      "fs.inotify.max_user_watches" = 524288;
    };
  };
}
