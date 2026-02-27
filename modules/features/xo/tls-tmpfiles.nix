# SPDX-License-Identifier: Apache-2.0
# XO Server TLS tmpfiles
{
  config,
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  tlsCfg = config.nixoa.xo.tls;
in
{
  config = mkIf vars.enableAutoCert {
    systemd.tmpfiles.rules = [
      "d ${tlsCfg.dir} 0755 root root - -"
    ];
  };
}
