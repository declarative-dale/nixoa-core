# SPDX-License-Identifier: Apache-2.0
# Centralized utility library for NiXOA modules

{ lib }:

let
  types = lib.types;
in

{
  # Custom types for enhanced validation
  customTypes = {
    systemdCalendar = types.strMatching "^([A-Za-z]+ [0-9]{2}:[0-9]{2}|daily|weekly|monthly)$"
      // { description = "systemd calendar expression"; };

    email = types.strMatching "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
      // { description = "valid email address"; };

    url = types.strMatching "^https?://.*"
      // { description = "HTTP or HTTPS URL"; };

    nonEmptyStr = types.strMatching ".+"
      // { description = "non-empty string"; };

    sshPublicKey = types.strMatching "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-).*"
      // { description = "SSH public key"; };
  };

  # Safe nested attribute access with default fallback
  # Replaces the duplicated 'get' pattern in 6 modules
  #
  # Usage: getOption systemSettings ["xo" "port"] 80
  # Returns: systemSettings.xo.port or 80 if not found
  getOption = settings: path: default:
    let
      getValue = cfg: pathList:
        if pathList == []
        then cfg
        else if builtins.isAttrs cfg && builtins.hasAttr (builtins.head pathList) cfg
        then getValue cfg.${builtins.head pathList} (builtins.tail pathList)
        else null;
      result = getValue settings path;
    in
      if result == null then default else result;

  # Helper to create a module option with common patterns
  mkDefaultOption = type: default: description: lib.mkOption {
    inherit type default description;
  };

  # Helper for enable options
  mkEnableOpt = description: lib.mkEnableOption description;

  # Service template helper
  mkSystemdService = { description, after ? [], requires ? [], wantedBy ? [ "multi-user.target" ], ... }@args:
    lib.filterAttrs (n: v: n != "description" && n != "after" && n != "requires" && n != "wantedBy") args // {
      inherit description after requires wantedBy;
    };

  # Path validation helper
  validatePath = path:
    assert lib.assertMsg (builtins.isString path && path != "") "Path must be a non-empty string";
    path;

  # Port validation helper
  validatePort = port:
    assert lib.assertMsg (builtins.isInt port && port > 0 && port < 65536) "Port must be between 1-65535";
    port;
}
