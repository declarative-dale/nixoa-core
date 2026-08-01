# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixoa.operator;
  inherit (lib) mkIf mkOption types;
  resolvePackage = item:
    lib.attrByPath
    (lib.splitString "." item)
    (throw "NiXOA package '${item}' was not found in pkgs")
    pkgs;
  mkServiceEnable = name:
    lib.setAttrByPath
    (lib.splitString "." name ++ ["enable"])
    true;
  nxcli = pkgs.callPackage ../../pkgs/nxcli/package.nix {
    repoRootDefault = cfg.repoDir;
  };
  nixoaMenu = pkgs.callPackage ../../pkgs/nixoa-menu/package.nix {
    repoRootDefault = cfg.repoDir;
  };
in {
  options.nixoa.operator = {
    username = mkOption {
      type = types.str;
      default = "nixoa";
      readOnly = true;
      description = "The fixed NiXOA operator account.";
    };
    repoDir = mkOption {
      type = types.str;
      default = "/home/nixoa/nixoa";
      description = "Path to the NiXOA checkout on the appliance.";
    };
    gitName = mkOption {
      type = types.str;
      default = "NiXOA Admin";
      description = "Git author name used by operator tooling.";
    };
    gitEmail = mkOption {
      type = types.str;
      default = "nixoa@nixoa";
      description = "Git author email used by operator tooling.";
    };
    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "SSH public keys authorized for the nixoa operator.";
    };
    enableExtras = lib.mkEnableOption "the expanded operator shell toolset";
    developmentMode = lib.mkEnableOption "development packages for working on NiXOA";
    menuAutoStart = lib.mkEnableOption "automatic nixoa-menu startup for SSH sessions";
    sudoNoPassword = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the operator may use sudo without a password.";
    };
    systemPackages = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional system package attribute paths.";
    };
    userPackages = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional Home Manager package attribute paths.";
    };
    menu = {
      extraSystemPackages = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "System packages managed by nixoa-menu.";
      };
      extraUserPackages = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "User packages managed by nixoa-menu.";
      };
      enabledServices = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "NixOS service option paths enabled by nixoa-menu.";
      };
    };
  };

  config = lib.mkMerge [
    {
      users.mutableUsers = true;
      users.users.${cfg.username} = {
        isNormalUser = true;
        description = "NiXOA operator";
        home = "/home/${cfg.username}";
        createHome = true;
        group = "users";
        extraGroups = [
          "wheel"
          "systemd-journal"
        ];
        hashedPassword = "!";
        openssh.authorizedKeys.keys = cfg.sshKeys;
        shell =
          if cfg.enableExtras
          then pkgs.zsh
          else pkgs.bashInteractive;
      };

      services = lib.mkMerge (
        [
          {
            openssh = {
              enable = true;
              openFirewall = true;
              settings = {
                PermitRootLogin = "no";
                PasswordAuthentication = false;
                KbdInteractiveAuthentication = false;
                PubkeyAuthentication = true;
                AllowUsers = [cfg.username];
                X11Forwarding = false;
                PermitEmptyPasswords = false;
                Protocol = 2;
                ClientAliveInterval = 300;
                ClientAliveCountMax = 2;
              };
            };
          }
        ]
        ++ map mkServiceEnable cfg.menu.enabledServices
      );

      security.sudo = {
        enable = true;
        wheelNeedsPassword = !cfg.sudoNoPassword;
        extraRules = lib.optionals cfg.sudoNoPassword [
          {
            users = [cfg.username];
            commands = [
              {
                command = "ALL";
                options = ["NOPASSWD"];
              }
            ];
          }
        ];
      };

      environment.shells = [pkgs.bashInteractive] ++ lib.optional cfg.enableExtras pkgs.zsh;
      programs = {
        bash.completion.enable = true;
        zsh.enable = cfg.enableExtras;
        git.enable = true;
        direnv = mkIf cfg.enableExtras {
          enable = true;
          nix-direnv.enable = true;
        };
      };

      environment.systemPackages =
        map resolvePackage (cfg.systemPackages ++ cfg.menu.extraSystemPackages)
        ++ [
          nxcli
          nixoaMenu
          pkgs.nh
        ];

      nixpkgs.config.allowUnfree = true;

      systemd.tmpfiles.rules = [
        "d /var/lib/nixoa 0755 root root - -"
        "d /home/${cfg.username}/.ssh 0700 ${cfg.username} users - -"
      ];

      systemd.services.nixoa-rebuild = {
        description = "Apply a queued NiXOA rebuild on boot";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        unitConfig.ConditionPathExists = "/var/lib/nixoa/rebuild-on-boot.env";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          set -euo pipefail
          queue_file=/var/lib/nixoa/rebuild-on-boot.env
          # shellcheck source=/var/lib/nixoa/rebuild-on-boot.env
          . "$queue_file"
          [ -n "''${repo_root:-}" ] || {
            echo "Queued NiXOA rebuild is missing repo_root." >&2
            exit 1
          }
          NIXOA_SYSTEM_ROOT="$repo_root" ${nxcli}/bin/nxcli apply
          rm -f "$queue_file"
        '';
      };
    }
    (mkIf cfg.developmentMode {
      environment.systemPackages = with pkgs; [
        devenv
        cargo
        clippy
        rust-analyzer
        rustc
        rustfmt
        rustup
        pkg-config
        corepack
        nodejs
        pnpm
        yarn
        redis
        valkey
      ];
    })
  ];
}
