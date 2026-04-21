# SPDX-License-Identifier: Apache-2.0
# XO storage sudo wrappers and config
{
  config,
  lib,
  pkgs,
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
    security.wrappers = lib.mkIf context.enableCIFS {
      "mount.cifs" = {
        program = "mount.cifs";
        source = "${lib.getBin pkgs.cifs-utils}/bin/mount.cifs";
        owner = "root";
        group = "root";
        setuid = true;
      };
    };

    security.sudo.extraConfig = ''
      Defaults !use_pty
      Defaults !log_subcmds
      Defaults:${cfg.user} !use_pty,!syslog
    '';
  };
}
