{ inputs, ... }:
let
  commonModules = [
    ../nixos/features/shared/args.nix
  ];

  platformModules =
    commonModules
    ++ [
      ../nixos/features/platform/boot/initrd.nix
      ../nixos/features/platform/identity/locale.nix
      ../nixos/features/platform/networking/defaults.nix
      ../nixos/features/platform/networking/firewall.nix
      ../nixos/features/platform/networking/nfs.nix
      ../nixos/features/platform/packages/packages.nix
      ../nixos/features/platform/services/journald.nix
      ../nixos/features/platform/services/prometheus.nix
    ];

  virtualizationModules =
    commonModules
    ++ [
      ../nixos/features/virtualization/xen-hardware.nix
      ../nixos/features/virtualization/xen-guest.nix
    ];

  xenOrchestraModules =
    commonModules
    ++ [
      ../nixos/features/xen-orchestra/options-base.nix
      ../nixos/features/xen-orchestra/options-paths.nix
      ../nixos/features/xen-orchestra/options-tls.nix
      ../nixos/features/xen-orchestra/config-link.nix
      ../nixos/features/xen-orchestra/service/account.nix
      ../nixos/features/xen-orchestra/service/assertions.nix
      ../nixos/features/xen-orchestra/service/limits.nix
      ../nixos/features/xen-orchestra/service/redis.nix
      ../nixos/features/xen-orchestra/service/packages.nix
      ../nixos/features/xen-orchestra/service/start-script.nix
      ../nixos/features/xen-orchestra/service/unit.nix
      ../nixos/features/xen-orchestra/service/tmpfiles.nix
      ../nixos/features/xen-orchestra/storage/libvhdi-options.nix
      ../nixos/features/xen-orchestra/storage/wrapper-script.nix
      ../nixos/features/xen-orchestra/storage/sudo-config.nix
      ../nixos/features/xen-orchestra/storage/packages.nix
      ../nixos/features/xen-orchestra/storage/filesystems.nix
      ../nixos/features/xen-orchestra/storage/sudo-rules.nix
      ../nixos/features/xen-orchestra/storage/sudo-init.nix
      ../nixos/features/xen-orchestra/storage/tmpfiles.nix
      ../nixos/features/xen-orchestra/storage/assertions.nix
      ../nixos/features/xen-orchestra/tls-service.nix
      ../nixos/features/xen-orchestra/tls-tmpfiles.nix
      ../nixos/features/xen-orchestra/cli.nix
    ];

  applianceModules = platformModules ++ virtualizationModules ++ xenOrchestraModules;

  mkModule = imports: {
    inherit imports;
    _module.args = {
      nixoaInputs = inputs;
    };
  };
in
{
  flake.nixosModules = {
    platform = mkModule platformModules;
    virtualization = mkModule virtualizationModules;
    xenOrchestra = mkModule xenOrchestraModules;
    appliance = mkModule applianceModules;
    default = mkModule applianceModules;
  };
}
