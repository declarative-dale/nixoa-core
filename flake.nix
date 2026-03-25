{
  description = "NiXOA Core - Xen Orchestra Community Edition deployment for NixOS homelabs";

  outputs =
    inputs:
    builtins.removeAttrs
      (
        (inputs.nixpkgs.lib.evalModules {
          modules = [
            ./modules/dendritic.nix
            ./modules/outputs
          ];
          specialArgs = { inherit inputs; };
        }).config.flake
      )
      [ "denful" ];

  inputs = {
    den.url = "github:vic/den";
    flake-aspects.url = "github:vic/flake-aspects";
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    xen-orchestra-ce = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+https://codeberg.org/NiXOA/xen-orchestra-ce.git?ref=beta";
    };
  };
}
