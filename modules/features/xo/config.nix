# SPDX-License-Identifier: Apache-2.0
# XO Server configuration - links config.nixoa.toml from system flake
{
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
in
{
  config = mkIf (vars.enableXO && vars.xoConfigFile != null) {
    environment.etc."xo-server/config.nixoa.toml" = {
      source = vars.xoConfigFile;
      mode = "0644";
    };
  };
}
