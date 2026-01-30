# SPDX-License-Identifier: Apache-2.0
# XO storage sudo rules
{
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf optionals;
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
  xoUser = vars.xoUser;
in
{
  config = mkIf storageEnabled {
    security.sudo = {
      enable = true;
      extraRules = [
        {
          users = [ xoUser ];
          commands =
            [
              {
                command = "/run/current-system/sw/bin/mount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/umount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/findmnt";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/wrappers/bin/mount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/wrappers/bin/umount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/wrappers/bin/findmnt";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/nix/store/*/bin/mount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/nix/store/*/bin/umount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/nix/store/*/bin/findmnt";
                options = [ "NOPASSWD" ];
              }
            ]
            ++ optionals vars.enableVHD [
              {
                command = "/run/current-system/sw/bin/vhdimount";
                options = [ "NOPASSWD" ];
              }
              {
                command = "/run/current-system/sw/bin/vhdiinfo";
                options = [ "NOPASSWD" ];
              }
            ];
        }
      ];
    };
  };
}
