{
  nixoa,
  ...
}:
{
  nixoa.platform.nixos.imports = [
    ../nixos/features/shared/context.nix
    ../nixos/features/platform/boot/initrd.nix
    ../nixos/features/platform/identity/locale.nix
    ../nixos/features/platform/networking/defaults.nix
    ../nixos/features/platform/networking/firewall.nix
    ../nixos/features/platform/networking/nfs.nix
    ../nixos/features/platform/packages/packages.nix
    ../nixos/features/platform/services/journald.nix
    ../nixos/features/platform/services/prometheus.nix
  ];
}
