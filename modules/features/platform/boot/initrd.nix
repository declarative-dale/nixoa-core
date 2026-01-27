# SPDX-License-Identifier: Apache-2.0
# Initrd and filesystem support
{ ... }:
{
  # Ensure NFS client utilities and services are available in initrd
  boot.initrd.supportedFilesystems = [ "nfs" ];
  boot.initrd.kernelModules = [ "nfs" ];

  # Enable systemd in initrd (required for repart)
  boot.initrd.systemd.enable = true;

  # Enable Partition Growth of root partition at boot
  boot.initrd.systemd.repart.enable = true;

  # Optional kernel parameters (useful for VMs and debugging)
  # boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];
}
