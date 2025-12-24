# SPDX-License-Identifier: Apache-2.0
# Home Manager configuration for NiXOA admin user
# Manages user-specific settings: shell, packages, dotfiles

{ config, lib, pkgs, username, userSettings ? {}, systemSettings ? {}, ... }:

let
  # Determine if extra terminal enhancements are enabled
  extrasEnabled = userSettings.extras.enable or false;

  # User-specific package list
  userPackages = userSettings.packages.extra or [];

  # Command for fzf to use fd (a fast find alternative) for file searching
  fdSearchCmd = "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
in
{
  # ==========================================================================
  # HOME MANAGER BASIC SETUP
  # ==========================================================================

  home.username = username;                           # Admin username (passed from system config, not hard-coded "xoa")
  home.homeDirectory = "/home/${username}";
  home.stateVersion = systemSettings.stateVersion or "25.11";

  # ==========================================================================
  # USER PACKAGES
  # ==========================================================================

  home.packages = with pkgs; (
    # Map each package name in userPackages to an actual package attribute from nixpkgs
    map (pkgName:
      if builtins.hasAttr pkgName pkgs
      then builtins.getAttr pkgName pkgs
      else throw "Package ${pkgName} not found in nixpkgs (check userSettings.packages.extra in configuration.nix)."
    ) userPackages
  ) ++ lib.optionals extrasEnabled [
    # Enhanced terminal tools (included only if extrasEnabled is true)
    oh-my-posh    # Themable shell prompt program
    bat           # Cat replacement with syntax highlighting
    eza           # Modern ls replacement
    fd            # Find replacement (used for fzf default search)
    ripgrep       # Rg, a faster grep alternative
    dust          # Du alternative for disk usage
    duf           # Disk usage utility with more features
    procs         # Improved ps command
    broot         # Tree navigation tool
    delta         # Improved diff for git
    jq            # JSON processor
    yq-go         # YAML processor (Go version of yq)
    gping         # Ping with graph output
    dog           # DNS lookup (dig replacement)
    bottom        # Modern top/htop alternative
    bandwhich     # Bandwidth utilization viewer
    tealdeer      # Tldr pages viewer
    lazygit       # Terminal UI for git
    gh            # GitHub CLI

    # =======================================================================
    # CUSTOM USER-DEFINED PACKAGES
    # =======================================================================
    # Add custom packages here that you want installed in your user environment
    # Example:
    #   - htop (system monitor)
    #   - tmux (terminal multiplexer)
    #   - neovim (text editor)
    #   - rust (programming language)
    # Simply add them to this list, or better yet, add them to [packages.user] extra
    # in your system-settings.toml so they're tracked in git
  ];

  # ==========================================================================
  # USER ENVIRONMENT (STORAGE PATHS, VARIABLES)
  # ==========================================================================

  home.sessionVariables = {
    # Expose the Xen Orchestra mounts directory as an environment variable
    XO_MOUNTS = systemSettings.storage.mountsDir or "/var/lib/xo/mounts";
  };

  # ==========================================================================
  # ZSH CONFIGURATION (when extras enabled)
  # ==========================================================================

  programs.zsh = lib.mkIf extrasEnabled {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;         # Zsh autosuggestions (typeahead suggestions)
    syntaxHighlighting.enable = true;     # Syntax highlighting for command line

    history = {
      size = 50000;                       # Large history file to remember lots of commands
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      ignoreAllDups = true;
      extended = true;
      share = true;                       # Share history across sessions
    };

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"                   # Git plugin (aliases and helpers)
        "sudo"                  # Easily repeat last command with sudo
        "docker"                # Docker command aliases/completion
        "kubectl"               # Kubectl integration
        "systemd"               # Systemd unit management aliases
        "ssh-agent"             # SSH agent plugin (manage keys)
        "command-not-found"     # Suggest installations for unknown commands
        "colored-man-pages"     # Colorize man pages
        "history-substring-search"  # Incremental history search (bound to arrow keys below)
      ];
    };

    shellAliases = {
      # Modern replacements for common commands
      ls = "eza --icons --group-directories-first";
      ll = "eza -l --icons --group-directories-first --git";
      la = "eza -la --icons --group-directories-first --git";
      lt = "eza --tree --level=2 --icons";
      cat = "bat --style=changes,header";               # Use bat for viewing files with changes highlighted
      catn = "bat --style=numbers,changes,header";      # Bat with line numbers

      # Navigation shortcuts (using zoxide under the hood)
      ".." = "cd ..";
      "..." = "cd ../..";
      cd = "z";    # Use zoxide's 'z' to jump to frequently used dirs
      cdi = "zi";  # Use zoxide's 'zi' for interactive directory selection (fzf)

      # Git command shortcuts
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline --graph --decorate";
      gd = "git diff";

      # System management shortcuts
      syslog = "journalctl -xe";                  # View system log errors
      sysfail = "systemctl --failed";             # Show failed systemd units
      sysrestart = "sudo systemctl restart";      # Restart a systemd service (usage: sysrestart <unit>)
      sysstatus = "sudo systemctl status";        # Check status of a systemd service (usage: sysstatus <unit>)
    };

    # Zsh initialization commands (only run if extrasEnabled)
    initContent = ''
      # Initialize the shell prompt with oh-my-posh (Night Owl theme for a nice look)
      eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${pkgs.oh-my-posh}/share/oh-my-posh/themes/night-owl.omp.json)"

      # (No manual zoxide init needed here — Home Manager's zoxide module takes care of it)
      # (No manual fzf export needed — configured via programs.fzf below)

      # Bind Up/Down arrows to history substring search (from oh-my-zsh plugin)
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down
      # (Ctrl+R is bound by fzf integration to open searchable command history)
    '';

    defaultKeymap = "emacs";  # Use Emacs keybindings in shell (e.g. Ctrl+A, Ctrl+E for navigation)
  };

  # ==========================================================================
  # TOOL CONFIGURATIONS (only when extras enabled)
  # ==========================================================================

  programs.bat = lib.mkIf extrasEnabled {
    enable = true;
    config = {
      theme = "Dracula";                   # Set bat's color theme
      style = "changes,header";            # Default style: show git changes and file header
      map-syntax = [
        "*.conf:INI"                      # Treat .conf files as INI for syntax highlighting
        ".ignore:Git Ignore"              # Treat .ignore like .gitignore syntax
      ];
    };
  };

  programs.git = lib.mkIf extrasEnabled {
    enable = true;
    settings = {
      init.defaultBranch = "main";         # Use 'main' as default branch name for new repos
      pull.rebase = true;                  # Default `git pull` to rebase
      core.pager = "${pkgs.delta}/bin/delta";                        # Use delta for paging diffs
      interactive.diffFilter = "${pkgs.delta}/bin/delta --color-only";  # Use delta for interactive hunk selection
      delta = {
        navigate = true;
        line-numbers = true;
        syntax-theme = "Dracula";
      };
      merge.conflictstyle = "diff3";       # Include base diff in merge conflicts
      diff.colorMoved = "default";         # Default moved lines coloring
    };
  };

  programs.direnv = lib.mkIf extrasEnabled {
    enable = true;
    nix-direnv.enable = true;             # Integrate direnv with Nix (nix-direnv)
    enableZshIntegration = true;          # Hook direnv into Zsh shell
  };

  programs.zoxide = lib.mkIf extrasEnabled {
    enable = true;
    enableZshIntegration = true;          # Enable zoxide and auto-initialize it in Zsh
  };

  programs.fzf = lib.mkIf extrasEnabled {
    enable = true;
    enableZshIntegration = true;
    # Use fd for default file search (Ctrl-T and general fzf) and bat for preview in fzf
    defaultCommand = fdSearchCmd;         # FZF_DEFAULT_COMMAND (list files using fd)
    fileWidgetCommand = fdSearchCmd;      # FZF_CTRL_T_COMMAND (also use fd for Ctrl-T)
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--preview \"${pkgs.bat}/bin/bat --color=always --style=numbers --line-range=:500 {}\""
    ];
  };

  # Bash configuration - always enabled for login shells
  programs.bash = {
    enable = true;
    enableCompletion = true;
    # Shell aliases only in interactive mode (not during login shell initialization)
    # This prevents syntax errors with aliases containing --flags during SSH login
  };

  # Let Home Manager manage itself (allows using the `home-manager` command for this user)
  programs.home-manager.enable = true;
}
