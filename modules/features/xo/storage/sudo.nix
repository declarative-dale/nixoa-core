# SPDX-License-Identifier: Apache-2.0
# XO storage sudo rules and init service
{
  config,
  lib,
  pkgs,
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

    systemd.services.xo-sudo-init = {
      description = "Initialize sudo for XO user";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "xo-sudo-init" ''
          if [ ! -f /var/db/sudo/lectured/${xoUser} ]; then
            mkdir -p /var/db/sudo/lectured
            touch /var/db/sudo/lectured/${xoUser}
            chown root:root /var/db/sudo/lectured/${xoUser}
            chmod 0600 /var/db/sudo/lectured/${xoUser}
          fi
        ''}";
      };
    };
  };
}
