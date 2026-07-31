{
  description = "NiXOA - a focused Xen Orchestra appliance for XCP-ng";

  # GitHub Actions publishes reusable package outputs to these caches. The
  # multi-gigabyte, closure-preseeded installer is a workflow artifact instead
  # so it does not consume the small NiXOA Cachix storage allocation.
  nixConfig = {
    extra-substituters = [
      "https://install.determinate.systems"
      "https://nixoa.cachix.org"
      "https://xen-orchestra-ce.cachix.org"
      "https://libvhdi-nixpkg.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
      "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
      "libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4="
    ];
  };

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
    xen-orchestra-ce.url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/heads/main";
  };
}
