# SPDX-License-Identifier: Apache-2.0
# Home Manager base settings
{osConfig, ...}: let
  cfg = osConfig.nixoa.operator;
in {
  home = {
    stateVersion = osConfig.system.stateVersion;
    username = cfg.username;
    homeDirectory = "/home/${cfg.username}";
  };

  programs.home-manager.enable = true;
}
