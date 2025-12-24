# SPDX-License-Identifier: Apache-2.0
# Core system services: journald, monitoring, and custom service definitions

{ config, pkgs, lib, systemSettings ? {}, nixoaUtils, ... }:

let
  inherit (nixoaUtils) getOption;

  # Extract commonly used values
  servicesDefinitions = getOption systemSettings ["services" "definitions"] {};
in
{
  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================

  # All services are defined here in one place to avoid conflicts
  # This includes built-in services, monitoring, logging, and custom services from nixoa.toml
  services = lib.mkMerge [
    {
      # libvhdi support for VHD operations
      libvhdi.enable = true;

      # Prometheus node exporter for monitoring (optional)
      prometheus.exporters.node = {
        enable = lib.mkDefault false;
        port = 9100;
        openFirewall = false;

        enabledCollectors = [
          "conntrack"
          "diskstats"
          "entropy"
          "filefd"
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "netstat"
          "stat"
          "time"
          "uname"
          "vmstat"
        ];
      };

      # Journald logging configuration
      journald.extraConfig = ''
        # Persistent storage
        Storage=persistent

        # Disk usage limits
        SystemMaxUse=1G
        SystemMaxFileSize=100M

        # Retention
        MaxRetentionSec=30d

        # Forward to console for debugging
        ForwardToConsole=no

        # Compression
        Compress=yes
      '';
    }
    # Custom services from user-config services.definitions
    # Users can define services with custom configurations
    # Note: Service names are validated by NixOS module system at evaluation time
    # Invalid service names will produce clear error messages
    servicesDefinitions
  ];
}
