# SPDX-License-Identifier: Apache-2.0
# Determinate Nix module
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.determinate;
in
{
  imports = [ inputs.determinate.nixosModules.default ];

  config = lib.mkIf cfg.enable {
    # The upstream Determinate NixOS module redirects generated Nix settings to
    # /etc/nix/nix.custom.conf. Keep Determinate-specific settings here so they
    # are only emitted when Determinate Nix is the active implementation.
    nix.settings = {
      eval-cores = lib.mkDefault 0;
      lazy-trees = lib.mkDefault true;
    };
  };
}
