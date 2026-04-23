# SPDX-License-Identifier: Apache-2.0
# Shared Nix settings for all hosts, including Determinate Nix
{ ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://xen-orchestra-ce.cachix.org"
    ];

    extra-trusted-public-keys = [
      "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
    ];

    trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
