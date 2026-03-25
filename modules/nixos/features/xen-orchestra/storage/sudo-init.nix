# SPDX-License-Identifier: Apache-2.0
# XO storage sudo init service
{
  config,
  lib,
  pkgs,
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
    systemd.services.xo-sudo-init = {
      description = "Initialize sudo for XO user";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "xo-sudo-init" ''
          if [ ! -f /var/db/sudo/lectured/${cfg.user} ]; then
            mkdir -p /var/db/sudo/lectured
            touch /var/db/sudo/lectured/${cfg.user}
            chown root:root /var/db/sudo/lectured/${cfg.user}
            chmod 0600 /var/db/sudo/lectured/${cfg.user}
          fi
        ''}";
      };
    };
  };
}
