{
  den,
  inputs,
  lib,
  ...
}: let
  systems = lib.unique (["x86_64-linux"] ++ builtins.attrNames den.hosts);
in {
  flake.formatter = lib.genAttrs systems (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in
    pkgs.writeShellApplication {
      name = "nixoa-format";
      runtimeInputs = [
        pkgs.alejandra
        pkgs.findutils
      ];
      text = ''
        if [ "$#" -gt 0 ]; then
          exec alejandra "$@"
        fi

        mapfile -d "" nix_files < <(find . -path ./.git -prune -o -type f -name "*.nix" -print0)
        if [ "''${#nix_files[@]}" -eq 0 ]; then
          exit 0
        fi

        exec alejandra "''${nix_files[@]}"
      '';
    });
}
