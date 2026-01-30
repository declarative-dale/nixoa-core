# SPDX-License-Identifier: Apache-2.0
# XO service start script
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
  xoaPackage = cfg.package;
  xoAppDir = "${xoaPackage}/libexec/xen-orchestra";
  startXO = pkgs.writeShellScript "xo-start.sh" ''
    set -euo pipefail
    export HOME="${cfg.home}"
    export NODE_ENV="production"
    exec ${pkgs.nodejs_24}/bin/node "${xoAppDir}/packages/xo-server/dist/cli.mjs" "$@"
  '';
in
{
  config = mkIf vars.enableXO {
    nixoa.xo.internal.startScript = startXO;
  };
}
