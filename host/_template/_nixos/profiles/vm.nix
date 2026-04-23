# SPDX-License-Identifier: Apache-2.0
# VM guest profile for a real installed appliance running inside a hypervisor
{ ... }:
{
  # Installed VM guests should remain bootable through the normal host boot
  # module and their copied hardware configuration. Do not disable the system
  # boot loader here; bootstrap now uses systemd-boot for VM targets too.
}
