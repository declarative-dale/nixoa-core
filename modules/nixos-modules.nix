{ lib, ... }:
let
  commonModules = [
    ./_nixos/features/foundation/args.nix
  ];

  platformModules =
    commonModules
    ++ [
      ./_nixos/features/platform/identity/hostname.nix
      ./_nixos/features/platform/identity/locale.nix
      ./_nixos/features/platform/identity/shells.nix
      ./_nixos/features/platform/identity/state-version.nix
      ./_nixos/features/platform/boot/loader.nix
      ./_nixos/features/platform/boot/initrd.nix
      ./_nixos/features/platform/users/accounts.nix
      ./_nixos/features/platform/users/sudo.nix
      ./_nixos/features/platform/users/ssh.nix
      ./_nixos/features/platform/networking/defaults.nix
      ./_nixos/features/platform/networking/firewall.nix
      ./_nixos/features/platform/networking/nfs.nix
      ./_nixos/features/platform/packages/base-packages.nix
      ./_nixos/features/platform/services/journald.nix
      ./_nixos/features/platform/services/prometheus.nix
    ];

  virtualizationModules = [
    ./_nixos/features/virtualization/xen-hardware.nix
    ./_nixos/features/virtualization/xen-guest.nix
  ];

  xoModules =
    commonModules
    ++ [
      ./_nixos/features/xo/options-base.nix
      ./_nixos/features/xo/options-paths.nix
      ./_nixos/features/xo/options-tls.nix
      ./_nixos/features/xo/config-link.nix
      ./_nixos/features/xo/service/assertions.nix
      ./_nixos/features/xo/service/redis.nix
      ./_nixos/features/xo/service/packages.nix
      ./_nixos/features/xo/service/start-script.nix
      ./_nixos/features/xo/service/unit.nix
      ./_nixos/features/xo/service/tmpfiles.nix
      ./_nixos/features/xo/storage/libvhdi-options.nix
      ./_nixos/features/xo/storage/wrapper-script.nix
      ./_nixos/features/xo/storage/sudo-config.nix
      ./_nixos/features/xo/storage/packages.nix
      ./_nixos/features/xo/storage/filesystems.nix
      ./_nixos/features/xo/storage/sudo-rules.nix
      ./_nixos/features/xo/storage/sudo-init.nix
      ./_nixos/features/xo/storage/tmpfiles.nix
      ./_nixos/features/xo/storage/assertions.nix
      ./_nixos/features/xo/tls-service.nix
      ./_nixos/features/xo/tls-tmpfiles.nix
      ./_nixos/features/xo/cli.nix
      ./_nixos/features/xo/dev-tools.nix
    ];

  applianceModules = platformModules ++ virtualizationModules ++ xoModules;

  mkModule = imports: { inherit imports; };
in
{
  flake.nixosModules = {
    platform = mkModule platformModules;
    xo = mkModule xoModules;
    appliance = mkModule applianceModules;
    default = mkModule applianceModules;
  };
}
