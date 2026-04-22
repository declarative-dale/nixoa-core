# SPDX-License-Identifier: Apache-2.0
# Firewall configuration from settings
{
  context,
  ...
}:
{
  networking.firewall.allowedTCPPorts = context.allowedTCPPorts;
  networking.firewall.allowedUDPPorts = context.allowedUDPPorts;
}
