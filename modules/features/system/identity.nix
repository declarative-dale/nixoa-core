# SPDX-License-Identifier: Apache-2.0
# System identification, locale, bootloader, and kernel configuration

{
  config,
  pkgs,
  lib,
  nixoaUtils,
  vars,
  ...
}:

{
  config = {
    # ============================================================================
    # SYSTEM IDENTIFICATION
    # ============================================================================

    networking.hostName = vars.hostname;

    # ============================================================================
    # LOCALE & INTERNATIONALIZATION
    # ============================================================================

    time.timeZone = lib.mkDefault vars.timezone;

    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_TIME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_ADDRESS = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
    };

    # ============================================================================
    # SHELLS
    # ============================================================================

    # Ensure both bash and zsh are valid login shells for the system
    # Shell selection per-user is configured in users.users.<name>.shell
    environment.shells = [
      pkgs.bashInteractive
      pkgs.zsh
    ];

    # ============================================================================
    # STATE VERSION
    # ============================================================================

    # DO NOT CHANGE after initial installation
    system.stateVersion = vars.stateVersion;
  };
}
