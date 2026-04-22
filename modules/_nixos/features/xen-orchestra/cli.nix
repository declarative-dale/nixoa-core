# SPDX-License-Identifier: Apache-2.0
# nxcli package and completion for XO-enabled hosts
{
  lib,
  pkgs,
  context,
  ...
}:
let
  inherit (lib) mkIf;

  nxcli = pkgs.nixoa.nxcli;

  nxcliCompletion = pkgs.writeTextFile {
    name = "nxcli-completion";
    destination = "/share/bash-completion/completions/nxcli";
    text = ''
      _nxcli_completion() {
        local cur prev words cword
        _init_completion || return

        local commands="help version status apply boot rollback host update xo generations"
        local host_subcommands="add list show select-vm edit help"
        local update_subcommands="flake xoa help"
        local xo_subcommands="logs help"
        local generations_subcommands="list help"

        case $cword in
          1)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
          2)
            case ''${words[1]} in
              host)
                COMPREPLY=($(compgen -W "$host_subcommands" -- "$cur"))
                ;;
              update)
                COMPREPLY=($(compgen -W "$update_subcommands" -- "$cur"))
                ;;
              xo)
                COMPREPLY=($(compgen -W "$xo_subcommands" -- "$cur"))
                ;;
              generations)
                COMPREPLY=($(compgen -W "$generations_subcommands" -- "$cur"))
                ;;
            esac
            ;;
        esac
      }

      complete -F _nxcli_completion nxcli
    '';
  };
in
{
  config = mkIf context.enableXO {
    environment.systemPackages = [
      nxcli
      nxcliCompletion
    ];

    programs.bash.completion.enable = true;
  };
}
