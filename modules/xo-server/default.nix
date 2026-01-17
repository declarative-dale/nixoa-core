# SPDX-License-Identifier: Apache-2.0
# XO Server modules - dynamic loader
{ lib, ... }:
let
  files = builtins.readDir ./.;
  nixFiles = lib.filterAttrs (
    n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix"
  ) files;
in
{
  imports = lib.mapAttrsToList (n: _: ./. + "/${n}") nixFiles;
}
