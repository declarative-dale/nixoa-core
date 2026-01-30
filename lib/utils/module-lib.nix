# SPDX-License-Identifier: Apache-2.0
# Common lib imports for modules
{ lib, ... }:
{
  moduleLib = {
    inherit (lib)
      mkOption
      mkDefault
      mkEnableOption
      mkIf
      mkMerge
      mkForce
      types
      ;
    inherit (lib.strings) concatStringsSep optionalString;
    inherit (lib.lists) optional optionals;
    inherit (lib.attrsets) mapAttrs' nameValuePair filterAttrs;
  };
}
