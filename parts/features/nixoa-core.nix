{
  ...
}:
{
  flake.modules.nixos.nixoaCore =
    {
      lib,
      vars ? { },
      ...
    }:
    let
      utils = import ../../lib/utils.nix { inherit lib; };
    in
    {
      imports = [ ../../modules ];

      _module.args = {
        nixoaUtils = utils;
        xoTomlData = null;
        inherit vars;
      };
    };
}
