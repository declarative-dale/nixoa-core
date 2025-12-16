# SPDX-License-Identifier: Apache-2.0
# xo-config.nix - Declarative XO server configuration
# ============================================================================
# Generates /etc/xo-server/config.toml from nixoa-config flake
# Only writes the file if the user flake provides config
# ============================================================================

{ config, lib, xoTomlData ? null, ... }:

let
  inherit (lib) mkIf;
in
{
  # Only generate the file if the user flake actually provides config
  config = mkIf (xoTomlData != null) {
    environment.etc."xo-server/config.toml" = {
      # xoTomlData is already a TOML-formatted string, use it directly
      text = xoTomlData;
      # Set permissions for the xo user (matches xoa.nix behavior)
      mode = "0640";
    };
  };
}
