# SPDX-License-Identifier: Apache-2.0
# XO storage assertions
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
    assertions = [
      {
        assertion =
          config.users.users.${cfg.user}.extraGroups or [ ] != [ ]
          -> builtins.elem "fuse" config.users.users.${cfg.user}.extraGroups;
        message = "XO user must be in 'fuse' group for remote storage mounting";
      }
      {
        assertion = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
        message = "At least one storage type must be enabled (NFS, CIFS, or VHD)";
      }
    ];
  };
}
