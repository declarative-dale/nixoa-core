{ inputs, ... }:
{
  imports = [
    ../../../_nixos/features/shared/context.nix
    (inputs.import-tree ../../../_nixos/features/virtualization)
  ];
}
