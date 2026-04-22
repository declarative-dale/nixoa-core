# SPDX-License-Identifier: Apache-2.0
# System packages from settings
{
  inputs,
  lib,
  pkgs,
  context,
  ...
}:
let
  resolvePackage =
    item:
    if builtins.isString item then
      lib.attrByPath
        (lib.splitString "." item)
        (throw "NiXOA system package '${item}' was not found in pkgs")
        pkgs
    else
      item;
  nixoaMenu = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nixoa-menu;
in
{
  environment.systemPackages =
    map resolvePackage (context.systemPackages or [ ])
    ++ map resolvePackage (context.extraSystemPackages or [ ])
    ++ [
      nixoaMenu
      pkgs.nh
    ];

  # Allow unfree packages needed by core/system package sets.
  nixpkgs.config.allowUnfree = true;
}
