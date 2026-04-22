# SPDX-License-Identifier: Apache-2.0
# XO Server path options
{
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;

  # Default home directory for XO service
  xoHome = "/var/lib/xo";
in
{
  options.nixoa.xo = {
    # Directory paths (advanced customization)
    home = mkOption {
      type = types.path;
      default = xoHome;
      description = "XO service home directory";
    };

    cacheDir = mkOption {
      type = types.path;
      default = "${xoHome}/.cache";
      description = "Cache directory for builds";
    };

    dataDir = mkOption {
      type = types.path;
      default = "${xoHome}/data";
      description = "Data directory for XO";
    };

    tempDir = mkOption {
      type = types.path;
      default = "${xoHome}/tmp";
      description = "Temporary directory for XO operations";
    };
  };
}
