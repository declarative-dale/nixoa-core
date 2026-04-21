{
  nixoa,
  ...
}:
{
  nixoa.virtualization.nixos.imports = [
    ../nixos/features/shared/context.nix
    ../nixos/features/virtualization/xen-hardware.nix
    ../nixos/features/virtualization/xen-guest.nix
  ];
}
