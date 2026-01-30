# SPDX-License-Identifier: Apache-2.0
# Virtualization feature registry
{ }:
{
  modules = {
    xen-hardware = [
      ../../../modules/features/virtualization/xen-hardware.nix
    ];
    xen-guest = [
      ../../../modules/features/virtualization/xen-guest.nix
    ];
  };

  order = [
    "xen-hardware"
    "xen-guest"
  ];
}
