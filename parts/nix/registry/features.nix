{
  lib,
  ...
}:
let
  feature = module: { inherit module; };

  commonModules = [
    ../../../modules/features/foundation/args.nix
  ];

  platformFeatures = [
    "system-identity"
    "system-boot"
    "system-users"
    "system-networking"
    "system-packages"
    "system-services"
  ];

  virtualizationFeatures = [
    "virtualization-xen-hardware"
    "virtualization-xen-guest"
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
      system-identity = feature ../../../modules/features/platform/identity;
      system-boot = feature ../../../modules/features/platform/boot;
      system-users = feature ../../../modules/features/platform/users;
      system-networking = feature ../../../modules/features/platform/networking;
      system-packages = feature ../../../modules/features/platform/packages;
      system-services = feature ../../../modules/features/platform/services;
      virtualization-xen-hardware = feature ../../../modules/features/virtualization/xen-hardware.nix;
      virtualization-xen-guest = feature ../../../modules/features/virtualization/xen-guest.nix;
      xo-options = feature ../../../modules/features/xo/options.nix;
      xo-config = feature ../../../modules/features/xo/config.nix;
      xo-service = feature ../../../modules/features/xo/service;
      xo-storage = feature ../../../modules/features/xo/storage;
      xo-tls = feature ../../../modules/features/xo/tls.nix;
      xo-cli = feature ../../../modules/features/xo/cli.nix;
      xo-extras = feature ../../../modules/features/xo/extras.nix;
    };

    stacks = {
      system = platformFeatures;
      xo = xoFeatures;
      appliance = platformFeatures ++ virtualizationFeatures ++ xoFeatures;
    };
  };
}
