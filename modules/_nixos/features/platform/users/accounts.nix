# SPDX-License-Identifier: Apache-2.0
# User and group management
{
  lib,
  pkgs,
  vars,
  ...
}:
{
  config = {
    systemd.tmpfiles.rules = [
      "d /home/${vars.username}/.ssh 0700 ${vars.username} users -"
    ];

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

    users.users.${vars.username} = {
      isNormalUser = true;
      description = "Xen Orchestra Administrator";
      createHome = true;
      home = "/home/${vars.username}";
      shell = if vars.enableExtras then pkgs.zsh else pkgs.bashInteractive;
      extraGroups = [
        "wheel"
        "systemd-journal"
      ];

      hashedPassword = "!";
      openssh.authorizedKeys.keys = vars.sshKeys;
    };
  };
}
