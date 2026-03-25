# SPDX-License-Identifier: Apache-2.0
# XO storage filesystem paths
{
  config,
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
in
{
  config = mkIf storageEnabled {
    systemd.tmpfiles.rules = [
      "d ${vars.mountsDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];
  };
}
