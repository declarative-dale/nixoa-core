# SPDX-License-Identifier: Apache-2.0
# System-level extras configuration
# NOTE: User-specific extras (zsh config, packages, dotfiles) are now managed by Home Manager
# This module only handles system-level requirements

{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  inherit (lib)
    mkIf
    ;
in
{
  config = lib.mkMerge [
    # Enable zsh system-wide when zsh is selected (required for it to be a valid login shell)
    (mkIf (vars.shell == "zsh") {
      programs.zsh.enable = true;
    })

    # Enable extras when explicitly enabled
    (mkIf vars.enableExtras {
      # Enable direnv system-wide (Home Manager will configure per-user)
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # Enable git system-wide (Home Manager will configure per-user)
      programs.git.enable = true;

      # Note: All user-specific configuration (shell config, packages, aliases, etc.)
      # is now handled by Home Manager in system/modules/home.nix
      #
      # The following have been moved to Home Manager:
      # - oh-my-posh prompt (enabled for both bash and zsh when extras are enabled)
      # - Terminal enhancement packages (bat, eza, fzf, etc.)
      # - User-specific git config
      # - bat configuration
      # - zoxide, fzf, and other tool initialization
      # - zsh configuration (oh-my-zsh, plugins, aliases, etc.) - only when zsh is selected
    })
  ];
}
