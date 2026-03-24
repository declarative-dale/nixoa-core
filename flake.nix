{
  description = "NiXOA Core - Xen Orchestra Community Edition deployment for NixOS homelabs";

  outputs =
    inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [ (inputs.import-tree ./modules) ];
      specialArgs = { inherit inputs; };
    }).config.flake;

  inputs = {
    den.url = "github:vic/den";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    flake-aspects.url = "github:vic/flake-aspects";
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "https://flakehub.com/f/nix-community/home-manager/0";
    };
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    xen-orchestra-ce = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+https://codeberg.org/NiXOA/xen-orchestra-ce.git?ref=beta";
    };
  };
}
