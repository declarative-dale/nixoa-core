# SPDX-License-Identifier: Apache-2.0
# Dynamic module bundler - automatically discovers and imports all .nix files
# in modules directory and its subdirectories (except bundle.nix and default.nix)

{ lib, ... }:

let
  modulesDir = ./.;

  # Recursively collect all .nix files from directory and subdirectories
  # Excludes: bundle.nix, default.nix, and home/ directory (handled separately in flake.nix)
  collectNixFiles = dir: prefix:
    let
      entries = builtins.readDir dir;
      processEntry = name: type:
        if type == "regular" && lib.hasSuffix ".nix" name && name != "bundle.nix" && name != "default.nix"
        then [ (prefix + name) ]
        else if type == "directory" && name != "home"
        then collectNixFiles (dir + "/${name}") (prefix + name + "/")
        else [ ];
    in
      lib.concatMap (name: processEntry name entries.${name}) (builtins.attrNames entries);

  # Get all .nix files relative to modules directory
  nixFiles = collectNixFiles modulesDir "";

  # Convert relative paths to module imports
  moduleImports = map (file: modulesDir + "/${file}") (lib.sort builtins.lessThan nixFiles);
in
{
  imports = moduleImports;
}
