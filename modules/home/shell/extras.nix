# SPDX-License-Identifier: Apache-2.0
# Shell tooling extras
{
  lib,
  pkgs,
  context,
  ...
}:
let
  fdSearchCmd = "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
in
{
  programs.direnv = lib.mkIf context.enableExtras {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.zoxide = lib.mkIf context.enableExtras {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.fzf = lib.mkIf context.enableExtras {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    defaultCommand = fdSearchCmd;
    fileWidgetCommand = fdSearchCmd;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
  };

  programs.oh-my-posh = lib.mkIf context.enableExtras {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    useTheme = "night-owl";
  };
}
