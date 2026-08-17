{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
in {
  flake.devShells = lib.genAttrs systems (system: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = package:
        lib.getName package == "packer";
    };
    secretspec = pkgs.callPackage ../../nix/pkgs/secretspec.nix {};
  in {
    default = pkgs.mkShellNoCC {
      packages = [
        pkgs.actionlint
        pkgs.alejandra
        pkgs.cargo
        pkgs.clippy
        pkgs.gh
        pkgs.jq
        pkgs.nixd
        pkgs.packer
        pkgs.rust-analyzer
        pkgs.rustc
        pkgs.rustfmt
        secretspec
        pkgs.shellcheck
        pkgs.zizmor
        pkgs.yq-go
      ];
    };
  });
}
