{
  den,
  inputs,
  lib,
  ...
}: let
  systems = lib.unique (["x86_64-linux"] ++ builtins.attrNames den.hosts);
in {
  flake.checks = lib.genAttrs systems (
    system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      packages = inputs.self.packages.${system};
    in {
      inherit
        (packages)
        metadata
        nxcli
        ;

      eval-smoke = pkgs.runCommandLocal "nixoa-core-eval-smoke" {} ''
        mkdir -p "$out"
        printf '%s\n' "NiXOA core flake evaluation smoke check" > "$out/README"
      '';
    }
  );
}
