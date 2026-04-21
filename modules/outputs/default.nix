{ inputs, ... }:
{
  imports = [
    inputs.den.flakeOutputs.packages
    ./packages.nix
  ];
}
