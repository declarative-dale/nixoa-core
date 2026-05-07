# SPDX-License-Identifier: Apache-2.0
# XO runtime packages
{
  lib,
  pkgs,
  context,
  ...
}: let
  inherit (lib) mkIf optionals unique;
  valkeyCompat =
    if builtins.hasAttr "valkey-compat-redis" pkgs
    then pkgs."valkey-compat-redis"
    else if builtins.hasAttr "valkey-compat" pkgs
    then pkgs."valkey-compat"
    else pkgs.valkey;
in {
  config = mkIf context.enableXO {
    environment.systemPackages = unique ([
        valkeyCompat
      ]
      ++ (with pkgs; [
        # Runtime + storage helpers
        rsync
        openssl
        fuse
        lvm2
        libguestfs
        ntfs3g

        # XO helper tooling
        git

        # Redis/Valkey tooling
        valkey
      ])
      ++ optionals context.enableNFS [pkgs.nfs-utils]
      ++ optionals context.enableCIFS [pkgs.cifs-utils]);
  };
}
