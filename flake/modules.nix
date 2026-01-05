# NixOS module exports
{ self, inputs, ... }:
{
  flake = {
    nixosModules.default = { config, lib, pkgs, ... }:
      let
        utils = import ../lib/utils.nix { inherit lib; };
      in
      {
        imports = [ ../modules ];

        _module.args = {
          nixoaPackages = self.packages.${pkgs.system};
          nixoaUtils = utils;
          xoTomlData = null;
        };
      };
  };
}
