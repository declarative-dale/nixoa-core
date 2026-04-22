# SPDX-License-Identifier: Apache-2.0
# Host-local NixOS composition for a concrete NiXOA appliance
{
  context,
  inputs,
  ...
}:
let
  profileImports =
    if (context.deploymentProfile or "physical") == "vm" then
      [ ./profiles/vm.nix ]
    else
      [ ./hardware-configuration.nix ];
in
{
  imports = [
    (inputs.import-tree ../../../modules/_nixos/runtime)
    (inputs.import-tree ../../../modules/_nixos/host)
  ] ++ profileImports;
}
