# SPDX-License-Identifier: Apache-2.0
# Host administrator account
{
  lib,
  context,
  ...
}:
let
  homeDir = "/home/${context.username}";
  repoDir = context.repoDir or "${homeDir}/nixoa";
in
{
  users.mutableUsers = false;

  systemd.tmpfiles.rules = [
    "d ${homeDir} 0755 ${context.username} users -"
    "d ${homeDir}/.ssh 0700 ${context.username} users -"
  ];

  system.activationScripts.nixoa-managed-home = lib.stringAfter [ "users" ] ''
    if [ -d ${lib.escapeShellArg homeDir} ]; then
      chown ${context.username}:users ${lib.escapeShellArg homeDir}
    fi

    if [ -d ${lib.escapeShellArg repoDir} ]; then
      chown -R ${context.username}:users ${lib.escapeShellArg repoDir}
    fi
  '';

  users.users.${context.username} = {
    isNormalUser = true;
    home = homeDir;
    createHome = true;
    description = "NiXOA administrator";
    group = "users";
    extraGroups = [
      "wheel"
      "systemd-journal"
    ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = context.sshKeys;
  };
}
