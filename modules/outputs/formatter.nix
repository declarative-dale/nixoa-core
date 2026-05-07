{
  den,
  inputs,
  lib,
  ...
}: let
  systems = lib.unique (["x86_64-linux"] ++ builtins.attrNames den.hosts);
in {
  flake.formatter = lib.genAttrs systems (
    system: inputs.nixpkgs.legacyPackages.${system}.alejandra
  );
}
