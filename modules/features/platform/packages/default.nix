# SPDX-License-Identifier: Apache-2.0
# Package + Nix settings bundle
{ ... }:
{
  imports = [
    ./system.nix
    ./nix-settings.nix
  ];
}
