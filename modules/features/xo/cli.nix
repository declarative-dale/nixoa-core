# SPDX-License-Identifier: Apache-2.0
# NiXOA CLI tool
{
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf;

  nixoa-cli = pkgs.writeShellApplication {
    name = "nixoa";
    runtimeInputs = with pkgs; [
      git
      coreutils
      gnused
      gawk
      nixos-rebuild
      nix
    ];
    text = builtins.readFile ../../../nixoa-cli.sh;
  };

  nixoa-completion = pkgs.writeTextFile {
    name = "nixoa-completion";
    destination = "/share/bash-completion/completions/nixoa";
    text = ''
      _nixoa_completion() {
          local cur prev words cword
          _init_completion || return

          local commands="config rebuild update rollback list-generations status version help"
          local config_subcommands="commit apply show diff history edit status help"

          case $cword in
              1)
                  COMPREPLY=($(compgen -W "$commands" -- "$cur"))
                  ;;
              2)
                  case ''${words[1]} in
                      config)
                          COMPREPLY=($(compgen -W "$config_subcommands" -- "$cur"))
                          ;;
                      rebuild)
                          COMPREPLY=($(compgen -W "switch test boot" -- "$cur"))
                          ;;
                  esac
                  ;;
          esac
      }

      complete -F _nixoa_completion nixoa
    '';
  };
in
{
  config = mkIf vars.enableXO {
    environment.systemPackages = [
      nixoa-cli
      nixoa-completion
    ];

    programs.bash.completion.enable = true;
  };
}
