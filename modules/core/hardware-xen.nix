# SPDX-License-Identifier: Apache-2.0
# Hardware configuration override for Xen VMs
# Overrides UUID-based filesystem declarations with device paths
# Xen VMs always have: xvda (boot: xvda1, root: xvda2, swap: xvda3)
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Override filesystem declarations to use device paths instead of UUIDs
  # This is required for systemd-repart to work properly with Xen VMs
  fileSystems."/" = lib.mkForce {
    device = "/dev/xvda2";
    fsType = "ext4";
  };

  fileSystems."/boot" = lib.mkForce {
    device = "/dev/xvda1";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # Override swap devices to use xvda3
  swapDevices = lib.mkForce [
    { device = "/dev/xvda3"; }
  ];
}
