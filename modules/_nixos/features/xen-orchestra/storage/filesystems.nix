# SPDX-License-Identifier: Apache-2.0
# XO storage filesystem support
{
  lib,
  context,
  ...
}:
let
  inherit (lib) mkIf optionals;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;
in
{
  config = mkIf storageEnabled {
    programs.fuse.userAllowOther = true;

    boot.kernelModules =
      [ "fuse" ]
      ++ optionals context.enableNFS [
        "nfs"
        "nfsv4"
      ]
      ++ optionals context.enableCIFS [ "cifs" ];

    boot.supportedFilesystems =
      optionals context.enableNFS [
        "nfs"
        "nfs4"
      ]
      ++ optionals context.enableCIFS [ "cifs" ];
  };
}
