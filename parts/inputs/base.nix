{
  ...
}:
{
  # Base inputs for the NiXOA core flake.
  flake-file.description = "NiXOA Core - Xen Orchestra Community Edition deployment for NixOS homelabs";

  flake-file.inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    home-manager = {
      url = "https://flakehub.com/f/nix-community/home-manager/0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xen-orchestra-ce = {
      url = "git+ssh://git@codeberg.org/NiXOA/xen-orchestra-ce.git?ref=refs/tags/v6.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
