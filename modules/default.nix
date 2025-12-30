# SPDX-License-Identifier: Apache-2.0
# NixOA system modules - organized by concern
# Explicitly imports all modules from subdirectories:
# - core/: system-level modules (no XO-specific logic)
# - xo/: XO-specific modules and integrations
# Note: home/ directory modules are handled separately in user-config

{
  imports = [
    # Core system modules (alphabetically ordered)
    ./core/base.nix
    ./core/boot.nix
    ./core/networking.nix
    ./core/packages.nix
    ./core/services.nix
    ./core/users.nix

    # XO-specific modules (alphabetically ordered)
    ./xo/autocert.nix
    ./xo/extras.nix
    ./xo/libvhdi.nix
    ./xo/nixoa-cli.nix
    ./xo/storage.nix
    ./xo/updates
    ./xo/xo-config.nix
    ./xo/xoa.nix
  ];
}
