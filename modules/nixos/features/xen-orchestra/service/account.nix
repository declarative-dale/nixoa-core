# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra service account
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixoa.xo;
in
{
  users.groups.${cfg.group} = { };
  users.groups.fuse = { };

  users.users.${cfg.user} = {
    isSystemUser = true;
    description = "Xen Orchestra service account";
    createHome = true;
    group = cfg.group;
    home = cfg.home;
    shell = lib.mkDefault "${pkgs.shadow}/bin/nologin";
    extraGroups = [ "fuse" ];
  };
}
