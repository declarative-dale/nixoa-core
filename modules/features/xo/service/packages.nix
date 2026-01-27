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
in
{
  config = mkIf vars.enableXO {
    environment.systemPackages = with pkgs; [
      rsync
      openssl
      fuse
      fuse3
      lvm2
      libguestfs
      ntfs3g
    ];
  };
}
