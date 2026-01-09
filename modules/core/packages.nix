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

  nix.settings = {
    # Binary cache configuration (system-wide)
    # Use extra-* to add to defaults rather than replace them
    extra-substituters = [
      "https://install.determinate.systems"
      "https://nixoa.cachix.org"
    ];

    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
    ];

    # Trusted users (needed to use flake-level nixConfig substituters)
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
}
