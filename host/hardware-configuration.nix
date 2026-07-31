# SPDX-License-Identifier: Apache-2.0
# Replaced with /etc/nixos/hardware-configuration.nix during bootstrap.
{...}: {
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
