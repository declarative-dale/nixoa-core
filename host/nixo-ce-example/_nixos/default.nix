# SPDX-License-Identifier: Apache-2.0
# Host-local NixOS composition for a concrete NiXOA appliance
{
  context,
  inputs,
  lib,
  ...
}: let
  extraNixosModules = context.extraNixosModules or [];
  extraNixosConfig = context.extraNixosConfig or {};
in {
  imports =
    [
      (inputs.import-tree ../../../modules/_nixos/runtime)
      (inputs.import-tree ../../../modules/_nixos/host)
      ./hardware-configuration.nix
    ]
    ++ extraNixosModules;

  config = lib.mkIf (extraNixosConfig != {}) extraNixosConfig;
}
