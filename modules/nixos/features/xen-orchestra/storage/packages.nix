# SPDX-License-Identifier: Apache-2.0
# XO storage packages and libvhdi
{
  config,
  lib,
  pkgs,
  context,
  ...
}:
let
  inherit (lib) mkIf optionals;
  storageEnabled = context.enableNFS || context.enableCIFS || context.enableVHD;
  cfg = config.services.libvhdi;
in
{
  config = mkIf storageEnabled {
    environment.systemPackages = optionals context.enableVHD [ cfg.package ];
    services.libvhdi.enable = context.enableVHD;
  };
}
