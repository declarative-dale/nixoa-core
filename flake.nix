{
  description = "NiXOA Core - Xen Orchestra Community Edition deployment for NixOS homelabs";

  outputs =
    inputs:
    builtins.removeAttrs
      (
        (inputs.nixpkgs.lib.evalModules {
          modules = [
            ./modules/den.nix
            ./modules/outputs
          ];
          specialArgs = { inherit inputs; };
        }).config.flake
      )
      [ "denful" ];

  inputs = {
    den.url = "github:vic/den";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    xen-orchestra-ce = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/tags/latest";
    };
  };
}
