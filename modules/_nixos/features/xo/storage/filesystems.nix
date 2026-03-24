# SPDX-License-Identifier: Apache-2.0
# XO storage filesystem support
{
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf optionals;
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
in
{
  config = mkIf storageEnabled {
    programs.fuse.userAllowOther = true;

    boot.kernelModules =
      [ "fuse" ]
      ++ optionals vars.enableNFS [
        "nfs"
        "nfsv4"
      ]
      ++ optionals vars.enableCIFS [ "cifs" ];

    boot.supportedFilesystems =
      optionals vars.enableNFS [
        "nfs"
        "nfs4"
      ]
      ++ optionals vars.enableCIFS [ "cifs" ];
  };
}
