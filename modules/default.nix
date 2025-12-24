# SPDX-License-Identifier: Apache-2.0
# NixOA system modules - organized by concern
# Dynamically imports all .nix files from subdirectories:
# - core/: system-level modules (no XO-specific logic)
# - xo/: XO-specific modules and integrations
# - home/: Home Manager configuration

{
  imports = [ ./bundle.nix ];
}
