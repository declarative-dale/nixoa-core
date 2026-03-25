# SPDX-License-Identifier: Apache-2.0
# Optional development tools
{
  lib,
  vars,
  ...
}:
let
  inherit (lib) mkIf;
in
{
  config = mkIf vars.enableExtras {
    programs.zsh.enable = true;

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    programs.git.enable = true;
  };
}
