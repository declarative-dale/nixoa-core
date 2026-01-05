# SPDX-License-Identifier: Apache-2.0
# System identification, locale, bootloader, and kernel configuration

{ config, pkgs, lib, nixoaUtils, ... }:

let
  inherit (lib) mkOption mkDefault types;
  inherit (nixoaUtils) getOption;

  # Extract commonly used values (support both old systemSettings and new config.nixoa.* pattern)
  hostname = config.nixoa.system.hostname;
  timezone = config.nixoa.system.timezone;
  stateVersion = config.nixoa.system.stateVersion;
in
{
  options.nixoa.system = {
    hostname = mkOption {
      type = types.str;
      default = "nixoa";
      description = "System hostname";
    };
    timezone = mkOption {
      type = types.str;
      default = "UTC";
      description = "System timezone (IANA timezone string)";
    };
    stateVersion = mkOption {
      type = types.str;
      default = "25.11";
      description = "NixOS state version (set during first installation, do not change)";
    };
  };

  config = {
    # ============================================================================
    # SYSTEM IDENTIFICATION
    # ============================================================================

    networking.hostName = hostname;

    # ============================================================================
    # LOCALE & INTERNATIONALIZATION
    # ============================================================================

    time.timeZone = lib.mkDefault timezone;

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
    environment.shells = [ pkgs.bashInteractive pkgs.zsh ];

    # ============================================================================
    # STATE VERSION
    # ============================================================================

    # DO NOT CHANGE after initial installation
    system.stateVersion = stateVersion;
  };
}
