{ config, pkgs, lib, ... }:

{
  # Garbage collection
  nix.gc = {
    automatic = true;
    dates     = "daily";
    options   = "--delete-older-than 7d";
  };

  # Auto-updates from this flake (edit the flake URI as needed)
  system.autoUpgrade = {
    enable       = false;
    flake        = ".#xoa";
    allowReboot  = false;
    frequency    = "daily";
    schedule     = "04:00";
    flags        = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
  };
}
