# SPDX-License-Identifier: Apache-2.0
# Bash configuration
{
  context,
  ...
}:
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    profileExtra = ''
      if [[ $- == *i* ]] && [[ -n "''${SSH_TTY:-}" ]] && [[ -t 0 ]] && [[ -t 1 ]] && [[ -z "''${NIXOA_TUI_BYPASS:-}" ]] && [[ -z "''${NIXOA_TUI_ACTIVE:-}" ]]; then
        export NIXOA_TUI_ACTIVE=1
        export NIXOA_SYSTEM_ROOT="''${NIXOA_SYSTEM_ROOT:-${context.repoDir or "/home/${context.username}/nixoa"}}"
        exec nixoa-menu
      fi
    '';
  };
}
