{
  lib,
  ...
}:
let
  feature = modules: { inherit modules; };

  commonModules = [
    ../../modules/features/foundation/args.nix
  ];
  platform = {
    modules = {
      identity = [
        ../../modules/features/platform/identity/hostname.nix
        ../../modules/features/platform/identity/locale.nix
        ../../modules/features/platform/identity/shells.nix
        ../../modules/features/platform/identity/state-version.nix
      ];
      boot = [
        ../../modules/features/platform/boot/loader.nix
        ../../modules/features/platform/boot/initrd.nix
      ];
      users = [
        ../../modules/features/platform/users/accounts.nix
        ../../modules/features/platform/users/sudo.nix
        ../../modules/features/platform/users/ssh.nix
      ];
      networking = [
        ../../modules/features/platform/networking/defaults.nix
        ../../modules/features/platform/networking/firewall.nix
        ../../modules/features/platform/networking/nfs.nix
      ];
      packages = [
        ../../modules/features/platform/packages/base-packages.nix
      ];
      services = [
        ../../modules/features/platform/services/journald.nix
        ../../modules/features/platform/services/prometheus.nix
      ];
    };

    order = [
      "identity"
      "boot"
      "users"
      "networking"
      "packages"
      "services"
    ];
  };
  virtualization = {
    modules = {
      xen-hardware = [
        ../../modules/features/virtualization/xen-hardware.nix
      ];
      xen-guest = [
        ../../modules/features/virtualization/xen-guest.nix
      ];
    };

    order = [
      "xen-hardware"
      "xen-guest"
    ];
  };
  xo = {
    modules = {
      options = [
        ../../modules/features/xo/options-base.nix
        ../../modules/features/xo/options-paths.nix
        ../../modules/features/xo/options-tls.nix
      ];
      config = [ ../../modules/features/xo/config-link.nix ];
      service = [
        ../../modules/features/xo/service/assertions.nix
        ../../modules/features/xo/service/redis.nix
        ../../modules/features/xo/service/packages.nix
        ../../modules/features/xo/service/start-script.nix
        ../../modules/features/xo/service/unit.nix
        ../../modules/features/xo/service/tmpfiles.nix
      ];
      storage = [
        ../../modules/features/xo/storage/libvhdi-options.nix
        ../../modules/features/xo/storage/wrapper-script.nix
        ../../modules/features/xo/storage/sudo-config.nix
        ../../modules/features/xo/storage/packages.nix
        ../../modules/features/xo/storage/filesystems.nix
        ../../modules/features/xo/storage/sudo-rules.nix
        ../../modules/features/xo/storage/sudo-init.nix
        ../../modules/features/xo/storage/tmpfiles.nix
        ../../modules/features/xo/storage/assertions.nix
      ];
      tls = [
        ../../modules/features/xo/tls-service.nix
        ../../modules/features/xo/tls-tmpfiles.nix
      ];
      cli = [ ../../modules/features/xo/cli.nix ];
      extras = [ ../../modules/features/xo/dev-tools.nix ];
    };

    order = [
      "options"
      "config"
      "service"
      "storage"
      "tls"
      "cli"
      "extras"
    ];
  };

  mkFeatureEntries =
    group: modulesByName:
    lib.mapAttrs'
      (name: modules: lib.nameValuePair "${group}-${name}" (feature modules))
      modulesByName;

  features =
    lib.foldl' lib.mergeAttrs { }
      (lib.mapAttrsToList mkFeatureEntries {
        platform = platform.modules;
        virtualization = virtualization.modules;
        xo = xo.modules;
      });

  platformStack = map (name: "platform-${name}") platform.order;
  virtualizationStack = map (name: "virtualization-${name}") virtualization.order;
  xoStack = map (name: "xo-${name}") xo.order;
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

    inherit features;

    stacks = {
      platform = platformStack;
      xo = xoStack;
      appliance = platformStack ++ virtualizationStack ++ xoStack;
    };
  };
}
