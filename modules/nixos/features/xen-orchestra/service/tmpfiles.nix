# SPDX-License-Identifier: Apache-2.0
# XO service filesystem layout
{
  config,
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
  xoUser = vars.xoUser;
  xoGroup = vars.xoGroup;
in
{
  config = mkIf vars.enableXO {
    systemd.tmpfiles.rules = [
      "d ${cfg.home}                          0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.cacheDir}                      0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.dataDir}                       0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.tempDir}                       0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.home}/.config                  0750 ${xoUser} ${xoGroup} - -"
      "d ${cfg.home}/.config/xo-server        0750 ${xoUser} ${xoGroup} - -"
      "d /etc/xo-server                       0755 root root - -"
      "d /var/lib/xo-server                   0750 ${xoUser} ${xoGroup} - -"
      "L+ ${cfg.home}/xen-orchestra           -    -        -        - ${cfg.package}/libexec/xen-orchestra"
    ];
  };
}
