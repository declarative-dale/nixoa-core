# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, vars, ... }:

let
  inherit (lib) mkOption mkEnableOption types mkIf;
  cfg = config.xoa.extras;
  username = vars.username;
in
{
  options.xoa.extras = {
    enable = mkEnableOption "Enhanced terminal experience for admin user" // { default = false; };
  };

  config = mkIf cfg.enable {
    # Set zsh as the default shell for the admin user
    users.users.${username}.shell = pkgs.zsh;

    # Enable zsh system-wide
    programs.zsh = {
      enable = true;

      # Enable completion system
      enableCompletion = true;

      # Enable bash completion compatibility
      enableBashCompletion = true;

      # Shell aliases available to all users
      shellAliases = {
        ls = "eza --icons --group-directories-first";
        ll = "eza -l --icons --group-directories-first --git";
        la = "eza -la --icons --group-directories-first --git";
        lt = "eza --tree --level=2 --icons";
        cat = "bat --style=changes,header";
        catn = "bat --style=numbers,changes,header";  # cat with line numbers
        ".." = "cd ..";
        "..." = "cd ../..";
      };

      # Auto-suggestions configuration
      autosuggestions = {
        enable = true;
        highlightStyle = "fg=8";
      };

      # Syntax highlighting
      syntaxHighlighting = {
        enable = true;
        highlighters = [ "main" "brackets" "pattern" ];
      };

      # History configuration
      histSize = 50000;
      histFile = "$HOME/.zsh_history";

      # Oh My Zsh configuration
      ohMyZsh = {
        enable = true;
        plugins = [
          "git"
          "sudo"
          "docker"
          "kubectl"
          "systemd"
          "ssh-agent"
          "command-not-found"
          "colored-man-pages"
          "history-substring-search"
        ];
      };

      # ZSH options for better UX
      setOptions = [
        "HIST_IGNORE_DUPS"        # Don't record duplicate commands
        "HIST_IGNORE_ALL_DUPS"    # Remove older duplicate entries from history
        "HIST_FIND_NO_DUPS"       # Don't display duplicates when searching
        "HIST_SAVE_NO_DUPS"       # Don't save duplicates
        "SHARE_HISTORY"           # Share history between sessions
        "APPEND_HISTORY"          # Append to history file
        "INC_APPEND_HISTORY"      # Add commands immediately
        "EXTENDED_HISTORY"        # Save timestamp and duration
        "HIST_EXPIRE_DUPS_FIRST"  # Expire duplicates first
        "HIST_VERIFY"             # Show command with history expansion before running
        "AUTO_CD"                 # cd by just typing directory name
        "CORRECT"                 # Auto correct mistakes
        "INTERACTIVE_COMMENTS"    # Allow comments in interactive shell
        "NO_NOMATCH"              # Don't error on failed glob matches
      ];

      # Additional shell init for all users
      interactiveShellInit = ''
        # Bind key for history substring search (up/down arrows)
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down

        # Better history search with Ctrl+R (will use fzf)
        bindkey '^R' fzf-history-widget

        # Initialize oh-my-posh with dracula theme
        eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${pkgs.oh-my-posh}/share/oh-my-posh/themes/night-owl.omp.json)"

        # Initialize zoxide (smarter cd)
        eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"

        # fzf configuration
        export FZF_DEFAULT_COMMAND='${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --preview "${pkgs.bat}/bin/bat --color=always --style=numbers --line-range=:500 {}"'

        # Initialize fzf key bindings and completion
        source ${pkgs.fzf}/share/fzf/key-bindings.zsh
        source ${pkgs.fzf}/share/fzf/completion.zsh

        # bat theme
        export BAT_THEME="Dracula"

        # Useful aliases for zoxide
        alias cd='z'
        alias cdi='zi'  # Interactive selection

        # Git aliases
        alias gs='git status'
        alias ga='git add'
        alias gc='git commit'
        alias gp='git push'
        alias gl='git log --oneline --graph --decorate'
        alias gd='git diff'

        # System aliases
        alias syslog='journalctl -xe'
        alias sysfail='systemctl --failed'
        alias sysrestart='sudo systemctl restart'
        alias sysstatus='sudo systemctl status'
      '';
    };

    # Install enhanced terminal tools
    environment.systemPackages = with pkgs; [
      # Shell enhancements
      oh-my-posh       # Prompt theme engine
      zoxide           # Smarter cd command
      fzf              # Fuzzy finder

      # Better CLI tools
      bat              # cat with syntax highlighting
      eza              # Modern ls replacement
      fd               # Better find
      ripgrep          # Better grep
      dust             # Better du
      duf              # Better df
      procs            # Better ps

      # File managers and viewers
      broot            # Better tree
      delta            # Better git diff

      # JSON/YAML tools
      jq               # JSON processor
      yq-go            # YAML processor

      # Network tools with better UX
      gping            # Ping with graph
      dog              # Better dig

      # System monitoring
      bottom           # Better top/htop
      bandwhich        # Network usage by process

      # Productivity
      tldr             # Simplified man pages
      tealdeer         # Fast tldr client

      # Git enhancements
      lazygit          # Terminal UI for git
      gh               # GitHub CLI
    ];

    # Configure bat (better cat)
    environment.etc."bat/config".text = ''
      --theme="Dracula"
      --style="changes,header"
      --map-syntax "*.conf:INI"
      --map-syntax ".ignore:Git Ignore"
    '';

    # Create user-specific zsh config directory
    system.activationScripts.extras-zsh = ''
      # Ensure .ssh directory exists for the admin user
      mkdir -p /home/${username}/.ssh
      chown ${username}:users /home/${username}/.ssh
      chmod 700 /home/${username}/.ssh

      # Create .zshrc for the admin user
      if [ ! -f /home/${username}/.zshrc ]; then
        cat > /home/${username}/.zshrc << 'EOF'
# Nix-managed zsh configuration
# Additional customizations can be added below this line

# Personal aliases and functions can go here

EOF
        chown ${username}:users /home/${username}/.zshrc
        chmod 644 /home/${username}/.zshrc
      fi

      # Ensure bat config directory exists for user
      mkdir -p /home/${username}/.config/bat
      chown -R ${username}:users /home/${username}/.config
    '';

    # Enable direnv for automatic environment loading
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Note: eza aliases are configured in zsh.shellAliases above

    # Enable git with better defaults
    programs.git = {
      enable = true;
      config = {
        init.defaultBranch = "main";
        pull.rebase = true;
        core.pager = "${pkgs.delta}/bin/delta";
        interactive.diffFilter = "${pkgs.delta}/bin/delta --color-only";
        delta = {
          navigate = true;
          line-numbers = true;
          syntax-theme = "Dracula";
        };
        merge.conflictstyle = "diff3";
        diff.colorMoved = "default";
      };
    };
  };
}
