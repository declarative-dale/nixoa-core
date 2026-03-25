# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra service account
{
  lib,
  pkgs,
  vars,
  ...
}:
{
  users.groups.${vars.xoGroup} = { };
  users.groups.fuse = { };

  users.users.${vars.xoUser} = {
    isSystemUser = true;
    description = "Xen Orchestra service account";
    createHome = true;
    group = vars.xoGroup;
    home = "/var/lib/xo";
    shell = lib.mkDefault "${pkgs.shadow}/bin/nologin";
    extraGroups = [ "fuse" ];
  };
}
