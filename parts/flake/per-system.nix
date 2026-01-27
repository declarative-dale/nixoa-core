{
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, self', ... }:
    {
      packages = {
        xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${pkgs.system}.xen-orchestra-ce;

        libvhdi = inputs.xen-orchestra-ce.packages.${pkgs.system}.libvhdi;

        default = self'.packages.xen-orchestra-ce;

        metadata = pkgs.stdenv.mkDerivation {
          pname = "nixoa-core-metadata";
          version = "1.2.0";
          dontUnpack = true;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/doc/nixoa-core
            echo "NiXOA Core - Xen Orchestra Community Edition on NixOS" > $out/share/doc/nixoa-core/README
            echo "This is a NixOS module library flake." >> $out/share/doc/nixoa-core/README
            echo "See https://codeberg.org/NiXOA/core for details." >> $out/share/doc/nixoa-core/README
          '';
          meta = with pkgs.lib; {
            description = "Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";
            license = licenses.asl20;
            maintainers = [
              {
                name = "Dale Morgan";
                codeberg = "dalemorgan";
              }
            ];
            platforms = platforms.linux;
            homepage = "https://codeberg.org/NiXOA/core";
          };
        };
      };

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
          echo "  ./modules/features/foundation/    - Shared module args"
          echo "  ./modules/features/platform/      - Base system features"
          echo "  ./modules/features/xo/            - XO features"
          echo "  ./modules/features/virtualization/ - VM hardware features"
          echo ""
          echo "📝 Available commands:"
          echo "  scripts/xoa-update.sh              - Update XO source code"
          echo "  nix flake check                    - Validate flake"
          echo "  nix flake show                     - Show flake outputs"
          echo ""
        '';
      };

      checks = { };
    };
}
