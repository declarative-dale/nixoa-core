# SPDX-License-Identifier: Apache-2.0
# XO storage filesystem paths
{
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
  xoUser = vars.xoUser;
  xoGroup = vars.xoGroup;
in
{
  config = mkIf storageEnabled {
    systemd.tmpfiles.rules = [
      "d ${vars.mountsDir} 0750 ${xoUser} ${xoGroup} - -"
    ];
  };
}
