# NixOS module exports
{ self, inputs, ... }:
{
  flake = {
    nixosModules.default = { config, lib, pkgs, vars ? {}, ... }:
      let
        utils = import ../lib/utils.nix { inherit lib; };
      in
      {
        imports = [ ../modules ];

        _module.args = {
          nixoaUtils = utils;
          xoTomlData = null;

          # Pass vars to all core modules
          inherit vars;
        };
      };
  };
}
