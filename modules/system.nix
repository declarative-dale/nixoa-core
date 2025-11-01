{ config, pkgs, lib, ... }:

{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  #Enable the Xen-Guest-Agent Service
  systemd.packages = [ pkgs.xen-guest-agent ];
  systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];
}
