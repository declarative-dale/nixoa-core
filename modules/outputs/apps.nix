{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
  mkNxcliApp = pkgs: nxcli: {
    appName,
    args,
    description,
  }: {
    type = "app";
    program = toString (
      pkgs.writeShellScript appName ''
        set -euo pipefail
        exec ${nxcli}/bin/nxcli ${lib.escapeShellArgs args} "$@"
      ''
    );
    meta.description = description;
  };
  mkRepoScriptApp = pkgs: {
    appName,
    scriptName,
    description,
  }: {
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
in {
  flake.apps = lib.genAttrs systems (
    system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      nxcli = inputs.self.packages.${system}.nxcli;
      nixoaMenu = inputs.self.packages.${system}.nixoa-menu;
      nxcliApp = mkNxcliApp pkgs nxcli;
    in {
      nxcli = {
        type = "app";
        program = "${nxcli}/bin/nxcli";
        meta.description = "Canonical NiXOA operator CLI";
      };

      apply = nxcliApp {
        appName = "nixoa-apply";
        args = ["apply"];
        description = "Apply a NiXOA host configuration through nxcli";
      };

      bootstrap = mkRepoScriptApp pkgs {
        appName = "nixoa-bootstrap";
        scriptName = "bootstrap.sh";
        description = "Bootstrap the fixed nixoa appliance checkout";
      };

      commit = nxcliApp {
        appName = "nixoa-commit";
        args = ["commit"];
        description = "Commit NiXOA repository changes through nxcli";
      };

      diff = nxcliApp {
        appName = "nixoa-diff";
        args = ["diff"];
        description = "Show NiXOA repository changes through nxcli";
      };

      history = nxcliApp {
        appName = "nixoa-history";
        args = ["history"];
        description = "Show NiXOA repository history through nxcli";
      };

      menu = {
        type = "app";
        program = "${nixoaMenu}/bin/nixoa-menu";
        meta.description = "Launch the NiXOA SSH administration TUI";
      };
    }
  );
}
