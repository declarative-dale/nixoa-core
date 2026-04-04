{ inputs, ... }:
{
  imports = [
    inputs.den.flakeOutputs.packages
    ./nixosModules.nix
    ./overlays.nix
    ./packages.nix
  ];
}
