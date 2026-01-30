# SPDX-License-Identifier: Apache-2.0
# libvhdi service options
{
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.services.libvhdi = {
    enable = lib.mkEnableOption "libvhdi library and tools for VHD/VHDX image access";

    package = mkOption {
      type = types.package;
      default = pkgs.nixoa.libvhdi;
      defaultText = lib.literalExpression "pkgs.nixoa.libvhdi";
      description = "libvhdi package to use";
    };
  };
}
