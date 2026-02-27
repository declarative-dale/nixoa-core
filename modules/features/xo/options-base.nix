# SPDX-License-Identifier: Apache-2.0
# XO Server core options
{
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.nixoa.xo = {
    # Advanced package override option
    package = mkOption {
      type = types.package;
      default = pkgs.nixoa.xen-orchestra-ce;
      defaultText = lib.literalExpression "pkgs.nixoa.xen-orchestra-ce";
      description = ''
        The Xen Orchestra package to run.

        To enable the optional yarn chmod sanitizer build workaround:

          nixoa.xo.package = pkgs.nixoa.xen-orchestra-ce.override { enableChmodSanitizer = true; };

        (Keep it off unless you hit EPERM chmod failures during build.)
      '';
    };

    # Advanced environment customization
    extraServerEnv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables for xo-server";
    };

    # Internal options (set by other modules, not user-facing)
    internal = {
      sudoWrapper = mkOption {
        type = types.nullOr types.package;
        default = null;
        internal = true;
        description = "Sudo wrapper package for CIFS credential injection (set by storage)";
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
