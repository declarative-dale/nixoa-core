# SPDX-License-Identifier: Apache-2.0
# Firewall defaults
{
  lib,
  ...
}:
{
  networking.firewall = {
    enable = true;
    allowPing = true;
    logRefusedConnections = lib.mkDefault false;
  };
}
