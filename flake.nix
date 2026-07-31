{
  description = "NiXOA - a focused Xen Orchestra appliance for XCP-ng";

  outputs = inputs:
    (
      inputs.nixpkgs.lib.evalModules {
        modules = [(inputs.import-tree ./modules)];
        specialArgs = {inherit inputs;};
      }
    ).config.flake;

  inputs = {
    den.url = "github:denful/den/v0.16.0";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "https://flakehub.com/f/nix-community/home-manager/0";
    };
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    xen-orchestra-ce.url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/tags/latest";
  };
}
