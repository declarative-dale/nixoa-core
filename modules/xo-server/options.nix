# SPDX-License-Identifier: Apache-2.0
# XO Server option definitions
{
  config,
  lib,
  pkgs,
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

    # TLS certificate paths
    tls = {
      dir = mkOption {
        type = types.path;
        default = "/etc/ssl/xo";
        description = "Directory for SSL certificates";
      };

      cert = mkOption {
        type = types.path;
        default = "/etc/ssl/xo/certificate.pem";
        description = "SSL certificate path";
      };

      key = mkOption {
        type = types.path;
        default = "/etc/ssl/xo/key.pem";
        description = "SSL private key path";
      };
    };

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
        description = "Sudo wrapper package for CIFS credential injection (set by storage.nix)";
      };
    };
  };

  # libvhdi service options
  options.services.libvhdi = {
    enable = lib.mkEnableOption "libvhdi library and tools for VHD/VHDX image access";

    package = mkOption {
      type = types.package;
      default = pkgs.nixoa.libvhdi;
      defaultText = lib.literalExpression "pkgs.nixoa.libvhdi";
      description = "libvhdi package to use";
    };
  };
}
