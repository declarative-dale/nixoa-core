# SPDX-License-Identifier: Apache-2.0
# XO storage packages and libvhdi
{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf optionals;
  storageEnabled = vars.enableNFS || vars.enableCIFS || vars.enableVHD;
  cfg = config.services.libvhdi;
in
{
  config = mkIf storageEnabled {
    environment.systemPackages =
      optionals vars.enableNFS [ pkgs.nfs-utils ]
      ++ optionals vars.enableCIFS [ pkgs.cifs-utils ]
      ++ optionals vars.enableVHD [ cfg.package ];

    services.libvhdi.enable = vars.enableVHD;
  };
}
