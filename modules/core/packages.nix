# SPDX-License-Identifier: Apache-2.0
# System packages and Nix configuration

{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    nano
    micro
    wget
    curl
    htop
    btop
    tree
    ncdu
    tmux

    # System administration
    git
    rsync
    lsof
    iotop
    sysstat
    dool  # dstat replacement

    # Network tools
    nfs-utils
    cifs-utils
    nettools
    nmap
    tcpdump
    dig
    traceroute
    snitch

    # XO dependencies
    nodejs_20
    yarn
    python3
    gcc
    gnumake
    pkg-config
    openssl

    # Monitoring
    prometheus-node-exporter
  ];

  # ============================================================================
  # NIX CONFIGURATION
  # ============================================================================

  nix = {
    # Enable flakes and new command interface
    settings = {
      experimental-features = [ "nix-command" "flakes" ];

      # Build optimization
      auto-optimise-store = true;

      # Trusted users (can use binary caches)
      trusted-users = [ "root" config.nixoa.admin.username ];

      # Prevent disk space issues
      min-free = lib.mkDefault (1024 * 1024 * 1024); # 1GB
      max-free = lib.mkDefault (5 * 1024 * 1024 * 1024); # 5GB
    };

    # Garbage collection
    gc = {
      automatic = lib.mkDefault false;
      dates = lib.mkDefault "weekly";
      options = lib.mkDefault "--delete-older-than 14d";
    };

    # Optimize store on a schedule
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };
}
