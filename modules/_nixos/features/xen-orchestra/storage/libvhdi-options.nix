# SPDX-License-Identifier: Apache-2.0
# libvhdi service options
{
  inputs,
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
      default = inputs.xen-orchestra-ce.packages.${pkgs.stdenv.hostPlatform.system}.libvhdi;
      defaultText = lib.literalExpression
        "inputs.xen-orchestra-ce.packages.${pkgs.stdenv.hostPlatform.system}.libvhdi";
      description = "libvhdi package to use";
    };
  };
}
