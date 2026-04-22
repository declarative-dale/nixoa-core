# SPDX-License-Identifier: Apache-2.0
# Default host networking: systemd-networkd with DHCP on Ethernet links
{ lib, ... }:
{
  networking.useDHCP = lib.mkForce false;
  networking.dhcpcd.enable = lib.mkForce false;

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;

    networks."10-uplink" = {
      matchConfig.Type = "ether";

      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };

      linkConfig.RequiredForOnline = "routable";
    };
  };
}
