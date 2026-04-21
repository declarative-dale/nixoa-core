{
  description = "NiXOA Core - Den-native aspect namespace for Xen Orchestra Community Edition hosts";

  outputs =
    inputs:
    (
      inputs.nixpkgs.lib.evalModules {
        modules = [
          ./modules/dendritic.nix
          ./modules/namespace.nix
          ./modules/aspects
          ./modules/outputs
        ];
        specialArgs = { inherit inputs; };
      }
    ).config.flake;

  inputs = {
    den.url = "github:vic/den";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    xen-orchestra-ce.url = "git+https://github.com/declarative-dale/xo-nixpkg.git?ref=refs/tags/latest";
  };
}
