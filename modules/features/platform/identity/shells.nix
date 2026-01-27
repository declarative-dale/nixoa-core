# SPDX-License-Identifier: Apache-2.0
# Shells available to user accounts
{
  pkgs,
  ...
}:
{
  environment.shells = [
    pkgs.bashInteractive
    pkgs.zsh
  ];
}
