# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  # NiXOA is always an XCP-ng guest. Disk and filesystem declarations are
  # intentionally left entirely to host/hardware-configuration.nix.
  systemd.packages = [pkgs.xen-guest-agent];
  systemd.services.xen-guest-agent.wantedBy = ["multi-user.target"];
}
