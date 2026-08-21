# SPDX-License-Identifier: Apache-2.0
# Hand-maintained settings for the single NiXOA appliance.
{lib, ...}: {
  networking.hostName = "nixoa";
  time.timeZone = "America/Chicago";
  system.stateVersion = "26.05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  nixoa.operator = {
    repoDir = "/home/nixoa/nixoa";
    gitName = "NiXOA Admin";
    gitEmail = "nixoa@nixoa";
    sshKeys = lib.mkDefault [];
    enableExtras = lib.mkDefault false;
    developmentMode = lib.mkDefault false;
    menuAutoStart = false;
    sudoNoPassword = true;
    systemPackages = [];
    userPackages = [];
  };

  nixoa.xo = {
    enable = true;
    httpHost = "0.0.0.0";
    tls = {
      enable = true;
      autoCert = true;
    };
    storage = {
      enableNFS = true;
      enableCIFS = true;
      enableVHD = true;
      mountsDir = "/var/lib/xo/mounts";
    };
  };
}
