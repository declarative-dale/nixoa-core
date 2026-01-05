# SPDX-License-Identifier: Apache-2.0
# Boot and bootloader configuration with systemd-boot as default

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    mkOption
    mkDefault
    mkIf
    types
    ;
in
{
  options.nixoa.boot = {
    loader = mkOption {
      type = types.enum [
        "systemd-boot"
        "grub"
      ];
      default = "systemd-boot";
      description = "Boot loader to use: systemd-boot (recommended for EFI) or grub (for BIOS/legacy boot)";
    };

    grub = {
      device = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GRUB device (e.g., /dev/sda or /dev/vda for Xen). Only used when loader is set to 'grub'.";
        example = "/dev/sda";
      };
    };

    efi = {
      canTouchEfiVariables = mkOption {
        type = types.bool;
        default = true;
        description = "Allow modifying EFI variables (required for systemd-boot on EFI systems)";
      };
    };
  };

  config = {
    # ============================================================================
    # BOOTLOADER CONFIGURATION
    # ============================================================================

    # Systemd-boot configuration (default)
    boot.loader.systemd-boot.enable = mkDefault (config.nixoa.boot.loader == "systemd-boot");
    boot.loader.efi.canTouchEfiVariables = mkIf (
      config.nixoa.boot.loader == "systemd-boot"
    ) config.nixoa.boot.efi.canTouchEfiVariables;

    # GRUB configuration (alternative for BIOS/legacy boot)
    # Only defined when loader is set to "grub"
    boot.loader.grub = mkIf (config.nixoa.boot.loader == "grub") {
      enable = true;
      device = config.nixoa.boot.grub.device;
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
