# SPDX-License-Identifier: Apache-2.0
# XO Server TLS path options
{
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.nixoa.xo.tls = {
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
}
