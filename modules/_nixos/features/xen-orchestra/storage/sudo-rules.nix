# SPDX-License-Identifier: Apache-2.0
# XO storage sudo rules
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
    security.sudo = {
      enable = true;
      extraRules = [
        {
          users = [ cfg.user ];
          commands = [
            {
              command = "${cfg.internal.storageHelper}/bin/xo-storage-helper";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
  };
}
