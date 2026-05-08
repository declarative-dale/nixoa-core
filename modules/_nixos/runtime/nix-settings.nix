# SPDX-License-Identifier: Apache-2.0
# Shared Nix settings for all hosts, including Determinate Nix
{...}: {
  nix.settings = {
    extra-substituters = [
      "https://xen-orchestra-ce.cachix.org"
      "https://libvhdi-nixpkg.cachix.org"
    ];

    extra-trusted-public-keys = [
      "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
      "libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4="
    ];

    trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
