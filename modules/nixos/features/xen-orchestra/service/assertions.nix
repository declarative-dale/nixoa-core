# SPDX-License-Identifier: Apache-2.0
# XO service assertions
{
  config,
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
in
{
  config = mkIf vars.enableXO {
    assertions = [
      {
        assertion = cfg.home != null;
        message = "XO home directory must be configured";
      }
    ];
  };
}
