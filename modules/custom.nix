{ config, pkgs, lib, vars, ... }:

# Custom packages and services module
# Allows users to add custom packages and enable services via nixoa.toml

{
  # ============================================================================
  # CUSTOM SERVICES CONFIGURATION
  # ============================================================================

  # Dynamically enable services from the enable list with default configs
  # Merge with any detailed service configurations from [services.name] sections
  services = lib.mkMerge [
    # Services from simple enable list (with default settings)
    (builtins.listToAttrs (
      map (serviceName: {
        name = serviceName;
        value = { enable = lib.mkDefault true; };
      }) vars.customServices.enableList
    ))
    # Detailed service configurations from TOML [services.servicename] sections
    vars.customServices.config
  ];
}
