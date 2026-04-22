# SPDX-License-Identifier: Apache-2.0
# XO Server configuration - links config.nixoa.toml from system flake
{
  lib,
  context,
  ...
}:
let
  inherit (lib) mkIf;
in
{
  config = mkIf (context.enableXO && context.xoConfigFile != null) {
    environment.etc."xo-server/config.nixoa.toml" = {
      source = context.xoConfigFile;
      mode = "0644";
    };
  };
}
