# SPDX-License-Identifier: Apache-2.0
# XO storage sudo init service
{
  lib,
  pkgs,
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
