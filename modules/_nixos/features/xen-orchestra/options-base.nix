# SPDX-License-Identifier: Apache-2.0
# XO Server core options
{
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkOption
    types
    ;
in {
  options.nixoa.xo = {
    user = mkOption {
      type = types.str;
      default = "xo";
      description = "System user that runs the Xen Orchestra services.";
    };

    group = mkOption {
      type = types.str;
      default = "xo";
      description = "Primary group for the Xen Orchestra service user.";
    };

    # Advanced package override option
    package = mkOption {
      type = types.package;
      default = pkgs.nixoa.xen-orchestra-ce;
      defaultText = lib.literalExpression "pkgs.nixoa.xen-orchestra-ce";
      description = ''
        The Xen Orchestra package to run.
      '';
    };

    # Advanced environment customization
    extraServerEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for xo-server";
    };

    config = {
      toml = mkOption {
        type = types.lines;
        default = "";
        description = "Complete TOML rendered to /etc/xo-server/config.nixoa.toml.";
      };
    };

    # Internal options (set by other modules, not user-facing)
    internal = {
      sudoWrapper = mkOption {
        type = types.nullOr types.package;
        default = null;
        internal = true;
        description = "Sudo wrapper package for CIFS credential injection (set by storage)";
      };

      storageHelper = mkOption {
        type = types.nullOr types.package;
        default = null;
        internal = true;
        description = "Root storage helper package for validated XO mount operations";
      };

      startScript = mkOption {
        type = types.nullOr types.path;
        default = null;
        internal = true;
        description = "Start script for xo-server (set by service module)";
      };
    };
  };
}
