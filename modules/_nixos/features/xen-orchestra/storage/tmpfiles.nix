# SPDX-License-Identifier: Apache-2.0
# XO storage filesystem paths
{
  config,
  lib,
  context,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;
in
{
  config = mkIf storageEnabled {
    systemd.tmpfiles.rules = [
      "d ${context.mountsDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];
  };
}
