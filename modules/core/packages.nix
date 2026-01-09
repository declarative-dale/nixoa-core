# SPDX-License-Identifier: Apache-2.0
# System packages and Nix configuration

{
  config,
  pkgs,
  lib,
  vars,
  ...
}:

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
    dool # dstat replacement

    # Network tools
    nfs-utils
    cifs-utils
    nettools
    nmap
    tcpdump
    dig
    traceroute

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

      # Build optimization
      auto-optimise-store = true;

      # Trusted users (can use binary caches)
      trusted-users = [
        "root"
        vars.username
      ];
    };

    # Note: Garbage collection and store optimization are automatically handled by Determinate Nix
    # which provides enhanced garbage collection and automatic cleanup
  };
}
