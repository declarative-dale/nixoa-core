# SPDX-License-Identifier: Apache-2.0
{
  description = "NixOA-VM - Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";

  inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    home-manager = {
      url = "https://flakehub.com/f/nix-community/home-manager/0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-file.url = "github:vic/flake-file";
    import-tree.url = "github:vic/import-tree";
    xoSrc = {
      url = "github:vatesfr/xen-orchestra/9b6d1089f4b96ef07d7ddc25a943c466e8c7bb4b";
      flake = false;
    };
    libvhdiSrc = {
      url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://install.determinate.systems"
      "https://nixoa.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
    ];
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./parts);
}
