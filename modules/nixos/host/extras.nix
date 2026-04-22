# SPDX-License-Identifier: Apache-2.0
# Extra operator tooling
{
  lib,
  pkgs,
  context,
  ...
}:
{
  environment.shells = [ pkgs.bashInteractive ] ++ lib.optionals context.enableExtras [ pkgs.zsh ];

  programs.zsh.enable = context.enableExtras;
  programs.git.enable = context.enableExtras;

  programs.direnv = lib.mkIf context.enableExtras {
    enable = true;
    nix-direnv.enable = true;
  };
}
