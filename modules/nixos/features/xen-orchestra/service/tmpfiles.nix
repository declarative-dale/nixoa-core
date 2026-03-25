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
in
{
  config = mkIf vars.enableXO {
    systemd.tmpfiles.rules = [
      "d ${cfg.home}                          0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.cacheDir}                      0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir}                       0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.tempDir}                       0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.home}/.config                  0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.home}/.config/xo-server        0750 ${cfg.user} ${cfg.group} - -"
      "d /etc/xo-server                       0755 root root - -"
      "d /var/lib/xo-server                   0750 ${cfg.user} ${cfg.group} - -"
      "L+ ${cfg.home}/xen-orchestra           -    -        -        - ${cfg.package}/libexec/xen-orchestra"
    ];
  };
}
