# SPDX-License-Identifier: Apache-2.0
# Network configuration and firewall rules

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ============================================================================
  # NETWORKING
  # ============================================================================

  # Enable networking
  networking.networkmanager.enable = lib.mkDefault false;
  systemd.network.enable = lib.mkDefault true;
  networking.useNetworkd = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;

  # Firewall configuration - ports are configured via vars in system flake
  networking.firewall = {
    enable = true;

    # Optional: Allow ping
    allowPing = true;

    # Log dropped packets (useful for debugging)
    logRefusedConnections = lib.mkDefault false;
  };

  # ============================================================================
  # NFS SUPPORT
  # ============================================================================

  # Enable rpcbind for NFSv3 support
  services.rpcbind.enable = true;
  services.nfs.server.enable = false; # We're a client, not a server
}
