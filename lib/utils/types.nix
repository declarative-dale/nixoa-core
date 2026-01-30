# SPDX-License-Identifier: Apache-2.0
# Custom types for NiXOA modules
{ lib, ... }:
let
  types = lib.types;
in
{
  customTypes = {
    systemdCalendar = types.strMatching "^([A-Za-z]+ [0-9]{2}:[0-9]{2}|daily|weekly|monthly)$" // {
      description = "systemd calendar expression";
    };

    email = types.strMatching "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$" // {
      description = "valid email address";
    };

    url = types.strMatching "^https?://.*" // {
      description = "HTTP or HTTPS URL";
    };

    nonEmptyStr = types.strMatching ".+" // {
      description = "non-empty string";
    };

    sshPublicKey = types.strMatching "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-).*" // {
      description = "SSH public key";
    };
  };
}
