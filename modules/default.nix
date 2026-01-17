# SPDX-License-Identifier: Apache-2.0
# NixOA modules - dynamic loader
{ lib, ... }:
let
  importDir =
    dir:
    let
      files = builtins.readDir dir;
      nixEntries = lib.filterAttrs (
        n: t:
        (t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix") || (t == "directory")
      ) files;
    in
    lib.mapAttrsToList (n: _: dir + "/${n}") nixEntries;
in
{
  imports = importDir ./core ++ importDir ./xo-server;
}
