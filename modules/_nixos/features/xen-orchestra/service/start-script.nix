# SPDX-License-Identifier: Apache-2.0
# XO service start script
{
  config,
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.nixoa.xo;
  xoaPackage = cfg.package;
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${cfg.home}"
    export NODE_ENV="production"
    exec ${xoaPackage}/bin/xo-server "$@"
  '';
in {
  config = mkIf context.enableXO {
    nixoa.xo.internal.startScript = startXO;
  };
}
