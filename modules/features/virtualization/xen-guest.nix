# SPDX-License-Identifier: Apache-2.0
# Xen Guest Agent configuration for better VM integration

{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  inherit (lib) mkIf;
in
{
  config = mkIf vars.enableXenGuest {
    # Xen guest agent for better VM integration
    systemd.packages = [ pkgs.xen-guest-agent ];
    systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];
  };
}
