# SPDX-License-Identifier: Apache-2.0
# System-level extras configuration
# NOTE: User-specific extras (zsh config, packages, dotfiles) are now managed by Home Manager
# This module only handles system-level requirements

{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption mkEnableOption types mkIf;
  cfg = config.xoa.extras;
in
{
  options.xoa.extras = {
    enable = mkEnableOption "Enhanced terminal experience for admin user" // { default = false; };
  };

  config = mkIf cfg.enable {
    # Enable zsh system-wide (required for it to be a valid login shell)
    programs.zsh.enable = true;

    # Enable direnv system-wide (Home Manager will configure per-user)
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Enable git system-wide (Home Manager will configure per-user)
    programs.git.enable = true;

    # Note: All user-specific configuration (shell config, packages, aliases, etc.)
    # is now handled by Home Manager in user-config/home/home.nix
    #
    # The following have been moved to Home Manager:
    # - zsh configuration (oh-my-zsh, plugins, aliases, etc.)
    # - oh-my-posh prompt
    # - Terminal enhancement packages (bat, eza, fzf, etc.)
    # - User-specific git config
    # - bat configuration
    # - zoxide, fzf, and other tool initialization
    # - Activation scripts for .zshrc creation
  };
}
