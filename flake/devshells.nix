# Development shells
{ ... }:
{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        jq
        git
        curl
        nixos-rebuild
        nix-tree
        nix-diff
      ];

      shellHook = ''
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║        NixOA Core Module Library - Dev Environment        ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "📋 This is the core module library (immutable, git-managed)"
        echo ""
        echo "📁 Module organization:"
        echo "  ./modules/core/     - System modules"
        echo "  ./modules/xo/       - XO-specific modules"
        echo ""
        echo "📝 Available commands:"
        echo "  nix run .#update-xo                - Update XO source code"
        echo "  nix flake check                    - Validate flake"
        echo "  nix flake show                     - Show flake outputs"
        echo ""
      '';
    };
  };
}
