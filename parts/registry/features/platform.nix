# SPDX-License-Identifier: Apache-2.0
# Platform feature registry
{ ... }:
{
  modules = {
    identity = [
      ../../../modules/features/platform/identity/hostname.nix
      ../../../modules/features/platform/identity/locale.nix
      ../../../modules/features/platform/identity/shells.nix
      ../../../modules/features/platform/identity/state-version.nix
    ];
    boot = [
      ../../../modules/features/platform/boot/loader.nix
      ../../../modules/features/platform/boot/initrd.nix
    ];
    users = [
      ../../../modules/features/platform/users/accounts.nix
      ../../../modules/features/platform/users/sudo.nix
      ../../../modules/features/platform/users/ssh.nix
    ];
    networking = [
      ../../../modules/features/platform/networking/defaults.nix
      ../../../modules/features/platform/networking/firewall.nix
      ../../../modules/features/platform/networking/nfs.nix
    ];
    packages = [
      ../../../modules/features/platform/packages/base-packages.nix
    ];
    services = [
      ../../../modules/features/platform/services/journald.nix
      ../../../modules/features/platform/services/prometheus.nix
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
}
