{
  description = "NiXOA - Den-native Xen Orchestra appliance flake with unified host management";

  outputs =
    inputs:
    (
      inputs.nixpkgs.lib.evalModules {
        modules = [
          ./modules/dendritic.nix
          ./modules/schema
          ./modules/namespace.nix
          ./modules/aspects
          ./modules/hosts
          ./modules/outputs
        ];
        specialArgs = { inherit inputs; };
      }
    ).config.flake;

  nixConfig = {
    extra-substituters = [ "https://xen-orchestra-ce.cachix.org" ];
    extra-trusted-public-keys = [
      "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
    ];
  };

  inputs = {
    den.url = "github:vic/den";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "https://flakehub.com/f/nix-community/home-manager/0";
    };
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    snitch = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:karol-broda/snitch";
    };
    xen-orchestra-ce.url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/tags/latest";
  };
}
