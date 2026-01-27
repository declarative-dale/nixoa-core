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
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
  xoUser = vars.xoUser;
in
{
  config = mkIf storageEnabled {
    assertions = [
      {
        assertion =
          config.users.users.${xoUser}.extraGroups or [ ] != [ ]
          -> builtins.elem "fuse" config.users.users.${xoUser}.extraGroups;
        message = "XO user must be in 'fuse' group for remote storage mounting";
      }
      {
        assertion = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
        message = "At least one storage type must be enabled (NFS, CIFS, or VHD)";
      }
    ];
  };
}
