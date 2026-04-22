# SPDX-License-Identifier: Apache-2.0
# Host-local NixOS composition for a concrete NiXOA appliance
{
  context,
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
    ../../modules/nixos/runtime/determinate.nix
    ../../modules/nixos/runtime/nix-settings.nix
    ../../modules/nixos/host/boot.nix
    ../../modules/nixos/host/network.nix
    ../../modules/nixos/host/state.nix
    ../../modules/nixos/host/time.nix
    ../../modules/nixos/host/packages.nix
    ../../modules/nixos/host/rebuild.nix
    ../../modules/nixos/host/services.nix
    ../../modules/nixos/host/extras.nix
    ../../modules/nixos/host/firewall.nix
    ../../modules/nixos/host/accounts.nix
    ../../modules/nixos/host/ssh.nix
    ../../modules/nixos/host/sudo.nix
  ] ++ profileImports;
}
