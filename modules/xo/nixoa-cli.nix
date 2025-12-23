# SPDX-License-Identifier: Apache-2.0
# NiXOA CE CLI tool module

{ config, lib, pkgs, ... }:

let
  inherit (lib) mkIf;

  # Create the nixoa CLI package
  nixoa-cli = pkgs.writeShellApplication {
    name = "nixoa";
    runtimeInputs = with pkgs; [ git coreutils gnused gawk nixos-rebuild nix ];
    text = builtins.readFile ../../nixoa-cli.sh;
  };

  # Bash completion for nixoa command
  nixoa-completion = pkgs.writeTextFile {
    name = "nixoa-completion";
    destination = "/share/bash-completion/completions/nixoa";
    text = ''
      # Bash completion for nixoa command
      _nixoa_completion() {
          local cur prev words cword
          _init_completion || return

          # First level commands
          local commands="config rebuild update rollback list-generations status version help"

          # Config subcommands
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
  config = mkIf config.xoa.enable {
    # Install the nixoa CLI tool system-wide
    environment.systemPackages = [
      nixoa-cli
      nixoa-completion
    ];

    # Ensure bash completion is enabled
    programs.bash.completion.enable = true;
  };
}
