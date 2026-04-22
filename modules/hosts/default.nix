{ lib, ... }:
let
  hostRoot = ../../hosts;
  isConcreteHost =
    name:
    let
      entry = builtins.readDir hostRoot;
    in
    entry.${name} == "directory" && name != "default" && builtins.pathExists (hostRoot + "/${name}/default.nix");
  hostNames = lib.filter isConcreteHost (builtins.attrNames (builtins.readDir hostRoot));
in
{
  imports = map (name: hostRoot + "/${name}") hostNames;
}
