{
  lib,
  ...
}:
let
  feature = module: { inherit module; };

  commonModules = [
    ../../modules/features/shared/args.nix
  ];

  systemFeatures = [
    "system-identity"
    "system-boot"
    "system-users"
    "system-networking"
    "system-packages"
    "system-services"
  ];

  virtualizationFeatures = [
    "virtualization-xen-hardware"
  ];

  xoFeatures = [
    "xo-options"
    "xo-config"
    "xo-service"
    "xo-storage"
    "xo-tls"
    "xo-cli"
    "xo-extras"
  ];
in
{
  options.flake.registry = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };

  config.flake.registry = {
    modules = {
      common = commonModules;
    };

    features = {
      system-identity = feature ../../modules/features/system/identity.nix;
      system-boot = feature ../../modules/features/system/boot.nix;
      system-users = feature ../../modules/features/system/users.nix;
      system-networking = feature ../../modules/features/system/networking.nix;
      system-packages = feature ../../modules/features/system/packages.nix;
      system-services = feature ../../modules/features/system/services.nix;
      virtualization-xen-hardware = feature ../../modules/features/virtualization/xen-hardware.nix;
      xo-options = feature ../../modules/features/xo/options.nix;
      xo-config = feature ../../modules/features/xo/config.nix;
      xo-service = feature ../../modules/features/xo/service.nix;
      xo-storage = feature ../../modules/features/xo/storage.nix;
      xo-tls = feature ../../modules/features/xo/tls.nix;
      xo-cli = feature ../../modules/features/xo/cli.nix;
      xo-extras = feature ../../modules/features/xo/extras.nix;
    };

    stacks = {
      system = systemFeatures;
      xo = xoFeatures;
      appliance = systemFeatures ++ virtualizationFeatures ++ xoFeatures;
    };
  };
}
