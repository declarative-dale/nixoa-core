# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.updates.autoUpgrade;
in
{
  options.updates.autoUpgrade = {
    enable = mkEnableOption "Automatic system upgrades using system.autoUpgrade";
    schedule = mkOption {
      type = types.str;
      default = "Sun 04:00";
      description = "When to check for updates (systemd calendar format)";
    };
    flake = mkOption {
      type = types.str;
      default = "";
      description = "Flake URI for system configuration (e.g., 'github:yourusername/user-config')";
    };
  };

  config = mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      dates = cfg.schedule;
      flake = cfg.flake;
      flags = [
        "--refresh"
        "-L"
      ];
      allowReboot = false;
    };
  };
}
