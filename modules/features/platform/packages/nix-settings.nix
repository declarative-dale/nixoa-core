# SPDX-License-Identifier: Apache-2.0
# Nix settings for caching and trust
{ ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://install.determinate.systems"
      "https://nixoa.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
    ];

    trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
