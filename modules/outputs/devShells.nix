{
  den,
  inputs,
  lib,
  ...
}:
let
  systems = lib.unique ([ "x86_64-linux" ] ++ builtins.attrNames den.hosts);
in
{
  flake.devShells = lib.genAttrs systems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in
    {
      default = pkgs.mkShell {
        packages = with pkgs; [
          curl
          git
          jq
          nh
          nix-diff
          nix-tree
          ripgrep
        ];

        shellHook = ''
          echo "NiXOA dev shell"
        '';
      };
    }
  );
}
