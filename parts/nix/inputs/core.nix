{
  ...
}:
{
  # Base inputs for the NiXOA core flake.
  flake-file.description = "NixOA-VM - Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";

  flake-file.nixConfig = {
    extra-substituters = [
      "https://install.determinate.systems"
      "https://nixoa.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
    ];
  };

  flake-file.inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    home-manager = {
      url = "https://flakehub.com/f/nix-community/home-manager/0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xen-orchestra-ce = {
      url = "git+ssh://git@codeberg.org/NiXOA/xen-orchestra-ce.git?ref=refs/tags/v1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
