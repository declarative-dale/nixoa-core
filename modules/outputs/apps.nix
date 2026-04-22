{
  den,
  inputs,
  lib,
  ...
}:
let
  systems = lib.unique ([ "x86_64-linux" ] ++ builtins.attrNames den.hosts);
  mkRepoScriptApp =
    pkgs:
    {
      appName,
      scriptName,
      description,
    }:
    {
      type = "app";
      program = toString (
        pkgs.writeShellScript appName ''
          set -euo pipefail

          repo_root="''${NIXOA_SYSTEM_ROOT:-}"
          if [ -z "$repo_root" ]; then
            if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
              repo_root="$git_root"
            else
              repo_root="$PWD"
            fi
          fi

          script="$repo_root/scripts/${scriptName}"
          if [ ! -x "$script" ]; then
            echo "Could not find $script" >&2
            echo "Run this app from a NiXOA checkout or set NIXOA_SYSTEM_ROOT." >&2
            exit 1
          fi

          exec "$script" "$@"
        ''
      );
      meta.description = description;
    };
  mkHostApps =
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      hostApps = den.lib.nh.hostApps {
        fromFlake = true;
        fromPath = ".";
      } pkgs;
      toApp = drv: {
        name = drv.name;
        value = {
          type = "app";
          program = "${drv}/bin/${drv.name}";
          meta.description = "Operate the ${drv.name} NiXOA host through nh";
        };
      };
    in
    lib.listToAttrs (map toApp hostApps);
in
{
  flake.apps = lib.genAttrs systems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      nixoaMenu = inputs.self.packages.${system}.nixoa-menu;
    in
    {
      apply = mkRepoScriptApp pkgs {
        appName = "nixoa-apply";
        scriptName = "apply-config.sh";
        description = "Apply a NiXOA host configuration through nh";
      };

      bootstrap = mkRepoScriptApp pkgs {
        appName = "nixoa-bootstrap";
        scriptName = "bootstrap.sh";
        description = "Bootstrap a NiXOA checkout and create a concrete host directory";
      };

      commit = mkRepoScriptApp pkgs {
        appName = "nixoa-commit";
        scriptName = "commit-config.sh";
        description = "Commit NiXOA repository changes";
      };

      diff = mkRepoScriptApp pkgs {
        appName = "nixoa-diff";
        scriptName = "show-diff.sh";
        description = "Show NiXOA repository changes";
      };

      history = mkRepoScriptApp pkgs {
        appName = "nixoa-history";
        scriptName = "history.sh";
        description = "Show NiXOA repository history";
      };

      menu = {
        type = "app";
        program = "${nixoaMenu}/bin/nixoa-menu";
        meta.description = "Launch the NiXOA SSH administration TUI";
      };
    }
    // mkHostApps system
  );
}
