# SPDX-License-Identifier: Apache-2.0
# XO runtime packages
{
  lib,
  pkgs,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
  valkeyCompat =
    if builtins.hasAttr "valkey-compat-redis" pkgs then
      pkgs."valkey-compat-redis"
    else if builtins.hasAttr "valkey-compat" pkgs then
      pkgs."valkey-compat"
    else
      pkgs.valkey;
in
{
  config = mkIf vars.enableXO {
    environment.systemPackages = lib.unique ([
      valkeyCompat
    ] ++ (with pkgs; [
      # Runtime + storage helpers
      rsync
      openssl
      fuse
      fuse3
      lvm2
      libguestfs
      ntfs3g
      nfs-utils
      cifs-utils

      # XO runtime
      git
      nodejs_24

      # Redis/Valkey tooling
      valkey
    ]));
  };
}
