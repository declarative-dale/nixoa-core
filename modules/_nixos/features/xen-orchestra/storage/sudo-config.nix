# SPDX-License-Identifier: Apache-2.0
# XO storage sudo wrappers and config
{
  config,
  lib,
  context,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;
in {
  config = mkIf storageEnabled {
    security.sudo.extraConfig = ''
      Defaults:${cfg.user} !use_pty,!log_subcmds,!syslog
    '';
  };
}
