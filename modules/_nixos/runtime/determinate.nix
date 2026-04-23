# SPDX-License-Identifier: Apache-2.0
# Determinate Nix module and supported custom config
{
  config,
  inputs,
  lib,
  ...
}:
let
  determinateEnabled = lib.attrByPath [ "determinate" "enable" ] false config;
in
{
  imports = [ inputs.determinate.nixosModules.default ];

  config = lib.mkIf determinateEnabled {
    environment.etc."nix/nix.custom.conf".text = lib.concatStringsSep "\n" [
      "# Managed by NiXOA for Determinate Nix."
      "# Determinate supports custom settings in /etc/nix/nix.custom.conf."
      "eval-cores = 0"
      "lazy-trees = true"
      ""
    ];
  };
}
