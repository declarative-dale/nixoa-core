# SPDX-License-Identifier: Apache-2.0
# Base platform packages
{
  pkgs,
  ...
}:
{
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
    dool
    openssl

    # Network tools
    nfs-utils
    cifs-utils
    nettools
    nmap
    tcpdump
    dig
    traceroute

    # Monitoring
    prometheus-node-exporter
  ];
}
