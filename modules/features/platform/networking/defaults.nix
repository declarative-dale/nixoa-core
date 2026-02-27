# SPDX-License-Identifier: Apache-2.0
# Networking defaults
{
  lib,
  ...
}:
{
  networking.networkmanager.enable = lib.mkDefault false;
  systemd.network.enable = lib.mkDefault true;
  networking.useNetworkd = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;
}
