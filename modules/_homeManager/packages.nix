# SPDX-License-Identifier: Apache-2.0
# User packages
{
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
        (throw "NiXOA user package '${item}' was not found in pkgs")
        pkgs
    else
      item;
in
{
  home.packages =
    map resolvePackage (context.userPackages or [ ])
    ++ map resolvePackage (context.extraUserPackages or [ ])
    ++ lib.optionals context.enableExtras [
      pkgs.bat
      pkgs.eza
      pkgs.fd
      pkgs.ripgrep
      pkgs.dust
      pkgs.duf
      pkgs.procs
      pkgs.broot
      pkgs.delta
      pkgs.jq
      pkgs.yq-go
      pkgs.nh
      pkgs.gping
      pkgs.dog
      pkgs.bottom
      pkgs.bandwhich
      pkgs.tealdeer
      pkgs.lazygit
      pkgs.gh
    ];
}
