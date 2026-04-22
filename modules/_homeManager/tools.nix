# SPDX-License-Identifier: Apache-2.0
# Extra tooling configuration
{
  lib,
  pkgs,
  context,
  ...
}:
{
  programs.bat = lib.mkIf context.enableExtras {
    enable = true;
    config = {
      theme = "Dracula";
      style = "changes,header";
      map-syntax = [
        "*.conf:INI"
        ".ignore:Git Ignore"
      ];
    };
  };

  programs.git = {
    enable = true;
    settings =
      {
        user.name = context.gitName;
        user.email = context.gitEmail;
        init.defaultBranch = "main";
        pull.rebase = true;
        merge.conflictstyle = "diff3";
        diff.colorMoved = "default";
      }
      // lib.optionalAttrs context.enableExtras {
        core.pager = "${pkgs.delta}/bin/delta";
        delta = {
          navigate = true;
          line-numbers = true;
          syntax-theme = "Dracula";
        };
      };
  };
}
