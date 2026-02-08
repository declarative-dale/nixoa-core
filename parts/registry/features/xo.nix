# SPDX-License-Identifier: Apache-2.0
# XO feature registry
{ ... }:
{
  modules = {
    options = [
      ../../../modules/features/xo/options-base.nix
      ../../../modules/features/xo/options-paths.nix
      ../../../modules/features/xo/options-tls.nix
    ];
    config = [ ../../../modules/features/xo/config-link.nix ];
    service = [
      ../../../modules/features/xo/service/assertions.nix
      ../../../modules/features/xo/service/redis.nix
      ../../../modules/features/xo/service/packages.nix
      ../../../modules/features/xo/service/start-script.nix
      ../../../modules/features/xo/service/unit.nix
      ../../../modules/features/xo/service/tmpfiles.nix
    ];
    storage = [
      ../../../modules/features/xo/storage/libvhdi-options.nix
      ../../../modules/features/xo/storage/wrapper-script.nix
      ../../../modules/features/xo/storage/sudo-config.nix
      ../../../modules/features/xo/storage/packages.nix
      ../../../modules/features/xo/storage/filesystems.nix
      ../../../modules/features/xo/storage/sudo-rules.nix
      ../../../modules/features/xo/storage/sudo-init.nix
      ../../../modules/features/xo/storage/tmpfiles.nix
      ../../../modules/features/xo/storage/assertions.nix
    ];
    tls = [
      ../../../modules/features/xo/tls-service.nix
      ../../../modules/features/xo/tls-tmpfiles.nix
    ];
    cli = [ ../../../modules/features/xo/cli.nix ];
    extras = [ ../../../modules/features/xo/dev-tools.nix ];
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
}
