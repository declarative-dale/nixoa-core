# SPDX-License-Identifier: Apache-2.0
# System identification, locale, bootloader, and kernel configuration

{ config, pkgs, lib, nixoaUtils, ... }:

let
  inherit (lib) mkOption mkDefault types;
  inherit (nixoaUtils) getOption;

  # Extract commonly used values (support both old systemSettings and new config.nixoa.* pattern)
  hostname = config.nixoa.system.hostname;
  timezone = config.nixoa.system.timezone;
  stateVersion = config.nixoa.system.stateVersion;
in
{
  options.nixoa.system = {
    hostname = mkOption {
      type = types.str;
      default = "nixoa";
      description = "System hostname";
    };
    timezone = mkOption {
      type = types.str;
      default = "UTC";
      description = "System timezone (IANA timezone string)";
    };
    stateVersion = mkOption {
      type = types.str;
      default = "25.11";
      description = "NixOS state version (set during first installation, do not change)";
    };
  };

  config = {
    # ============================================================================
    # SYSTEM IDENTIFICATION
    # ============================================================================

    networking.hostName = hostname;

    # ============================================================================
    # LOCALE & INTERNATIONALIZATION
    # ============================================================================

    time.timeZone = lib.mkDefault timezone;

    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_TIME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_ADDRESS = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
    };

    # ============================================================================
    # SHELLS
    # ============================================================================

    # Ensure both bash and zsh are valid login shells for the system
    # Shell selection per-user is configured in users.users.<name>.shell
    environment.shells = [ pkgs.bashInteractive pkgs.zsh ];

    # ============================================================================
    # BOOTLOADER
    # ============================================================================

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Alternative for VMs using BIOS/legacy boot:
    # boot.loader.grub = {
    #   enable = true;
    #   device = "/dev/sda";  # or /dev/vda, /dev/xvda for Xen
    # };

    # ============================================================================
    # KERNEL & FILESYSTEM SUPPORT
    # ============================================================================

    # Note: Filesystem support (NFS, CIFS) is configured in storage.nix
    # to avoid duplication and ensure consistency

    # Note: All services configuration is consolidated below after the Nix configuration section
    # to avoid conflicts with custom services from nixoa.toml

    # Ensure NFS client utilities and services are available
    boot.initrd.supportedFilesystems = [ "nfs" ];
    boot.initrd.kernelModules = [ "nfs" ];

    # Kernel parameters (optional, useful for VMs)
    # boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

    # ============================================================================
    # XEN GUEST SUPPORT
    # ============================================================================

    # Xen guest agent for better VM integration
    systemd.packages = [ pkgs.xen-guest-agent ];
    systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];

    # ============================================================================
    # PERFORMANCE TUNING
    # ============================================================================

    # Swappiness (lower = less swap usage)
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

    # ============================================================================
    # STATE VERSION
    # ============================================================================

    # DO NOT CHANGE after initial installation
    system.stateVersion = stateVersion;
  };
}
