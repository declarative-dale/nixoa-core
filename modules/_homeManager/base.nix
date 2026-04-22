# SPDX-License-Identifier: Apache-2.0
# Home Manager base settings
{ context, ... }:
{
  home = {
    stateVersion = context.stateVersion;
    username = context.username;
    homeDirectory = "/home/${context.username}";
  };

  programs.home-manager.enable = true;
}
