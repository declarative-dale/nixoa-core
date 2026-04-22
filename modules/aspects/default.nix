{ ... }:
{
  imports = [
    ./defaults.nix
    ./platform.nix
    ./virtualization.nix
    ./xen-orchestra.nix
    ./appliance.nix
  ];
}
