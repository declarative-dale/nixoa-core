{ inputs, ... }:
{
  imports = [
    inputs.den.flakeOutputs.apps
    inputs.den.flakeOutputs.devShells
    inputs.den.flakeOutputs.packages
    ./apps.nix
    ./devShells.nix
    ./packages.nix
  ];
}
