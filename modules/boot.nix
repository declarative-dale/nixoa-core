{ config, lib, pkgs, ... }:

{ 
# Bootloader.
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
# Example for a typical VM using GRUB:
#  boot.loader.grub = {
#    enable = true;
#    device = "/dev/sda";  # or /dev/vda or /dev/xvda as in your old config
#  };
}