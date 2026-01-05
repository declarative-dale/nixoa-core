# Application definitions
{ ... }:
{
  perSystem = { pkgs, ... }: {
    apps.update-xo = {
      type = "app";
      program = toString (pkgs.writeShellApplication {
        name = "update-xo";
        runtimeInputs = [ pkgs.jq pkgs.git pkgs.curl ];
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "🔄 Updating Xen Orchestra source..."
          nix flake lock --update-input xoSrc

          echo "📋 Recent commits in xen-orchestra:"
          curl -s https://api.github.com/repos/vatesfr/xen-orchestra/commits?per_page=5 | \
            jq -r '.[] | "  • \(.sha[0:7]) - \(.commit.message | split("\n")[0]) (\(.commit.author.date))"'

          echo ""
          echo "✅ Update complete! Review changes with: git diff flake.lock"
          echo ""
          echo "📦 To rebuild with core updates:"
          echo "   cd ~/projects/NiXOA/system && sudo nixos-rebuild switch --flake ."
        '';
      });
      meta = with pkgs.lib; {
        description = "Update the xoSrc input in flake.lock and show new commits.";
        license = licenses.asl20;
        platforms = platforms.linux;
      };
    };
  };
}
