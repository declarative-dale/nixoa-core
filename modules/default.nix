# SPDX-License-Identifier: Apache-2.0
# Auto-import all .nix modules in this directory
{ lib, ... }:

let
  # Read all files in the modules directory
  modulesDir = ./.;

  # Get list of .nix files (excluding default.nix itself)
  moduleFiles = builtins.filter
    (name: name != "default.nix" && lib.hasSuffix ".nix" name)
    (builtins.attrNames (builtins.readDir modulesDir));

  # Convert filenames to paths
  modulePaths = map (name: modulesDir + "/${name}") moduleFiles;
in
{
  imports = modulePaths;
}
