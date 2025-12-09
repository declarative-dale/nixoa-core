# SPDX-License-Identifier: Apache-2.0
# xo-config.nix - Declarative XO server configuration
# ============================================================================
# Generates /etc/xo-server/config.toml from nixoa-config flake
# Only writes the file if the user flake provides config
# ============================================================================

{ config, lib, nixoa-config ? null, ... }:

let
  inherit (lib) mkIf;

  xoTomlData =
    if nixoa-config != null && nixoa-config ? nixoa &&
       nixoa-config.nixoa ? xoServer && nixoa-config.nixoa.xoServer ? toml
    then nixoa-config.nixoa.xoServer.toml
    else null;
in
{
  # Only generate the file if the user flake actually provides config
  config = mkIf (xoTomlData != null) {
    environment.etc."xo-server/config.toml" = {
      text = lib.generators.toTOML {} xoTomlData;
      # Set permissions for the xo user (matches xoa.nix behavior)
      mode = "0640";
    };
  };
}
