# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.updates.gc;
in
{
  options.updates.gc = {
    enable = mkEnableOption "Automatic garbage collection";
    schedule = mkOption {
      type = types.str;
      default = "monthly";
      description = "When to run GC (systemd calendar format, e.g., 'daily', 'weekly', 'monthly', 'Sun 04:00', '*-*-01 04:00')";
    };
    keepDays = mkOption {
      type = types.int;
      default = 30;
      description = "Delete generations older than this many days";
    };
  };

  config = mkIf cfg.enable {
    nix.gc = {
      automatic = true;
      dates = cfg.schedule;
      options = "";
    };
    nix.optimise.automatic = true;
    nix.optimise.dates = [ cfg.schedule ];
  };
}
