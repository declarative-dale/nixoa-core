{
  ...
}:
{
  # Base inputs for the NiXOA core flake.
  flake-file.inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    home-manager = {
      url = "https://flakehub.com/f/nix-community/home-manager/0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xoSrc = {
      url = "github:vatesfr/xen-orchestra/9b6d1089f4b96ef07d7ddc25a943c466e8c7bb4b";
      flake = false;
    };
    libvhdiSrc = {
      url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
      flake = false;
    };
  };
}
