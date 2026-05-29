# SPDX-License-Identifier: Apache-2.0
# XO Server TLS tmpfiles
{
  config,
  lib,
  context,
  ...
}: let
  inherit (lib) mkIf;
  tlsCfg = config.nixoa.xo.tls;
  autoCertEnabled = context.enableXO && context.enableTLS && context.enableAutoCert;
in {
  config = mkIf autoCertEnabled {
    systemd.tmpfiles.rules = [
      "d ${tlsCfg.dir} 0755 root root - -"
    ];
  };
}
