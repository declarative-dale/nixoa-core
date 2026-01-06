# Dynamically import all flake-parts modules in this directory
{ lib, ... }:
let
  # Read all files in the flake directory
  files = builtins.readDir ./.;

  # Filter to only .nix files, excluding default.nix itself
  nixFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) files;

  # Convert to list of import paths
  modules = lib.mapAttrsToList (name: _: ./. + "/${name}") nixFiles;
in
{
  imports = modules;
}
