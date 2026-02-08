# DO-NOT-EDIT. This file was auto-generated using github:vic/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "NiXOA Core - Xen Orchestra Community Edition deployment for NixOS homelabs";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./parts);

  inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    flake-file.url = "github:vic/flake-file";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "https://flakehub.com/f/nix-community/home-manager/0";
    };
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    xen-orchestra-ce = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+ssh://git@codeberg.org/NiXOA/xen-orchestra-ce.git?ref=refs/tags/v6.1.1";
    };
  };

}
