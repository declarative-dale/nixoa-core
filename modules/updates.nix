{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;

  cfg = config.updates;

  # Script: keep only last N successful system generations, then GC + optimise.
  gcScript = pkgs.writeShellApplication {
    name = "xoa-gc-keep-last";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.nix pkgs.nix-output-monitor ];
    text = ''
      set -euo pipefail

      KEEP="${toString cfg.gc.keepGenerations}"
      PROFILE="/nix/var/nix/profiles/system"

      # List generations, keep only the newest KEEP, delete the rest.
      gens="$(nix-env -p "$PROFILE" --list-generations | awk "{print \$1}")" || gens=""
      if [ -z "$gens" ]; then
        echo "No generations found; nothing to delete."
      else
        keep="$(echo "$gens" | tail -n "$KEEP")"
        del="$(comm -23 <(echo "$gens" | sort -n) <(echo "$keep" | sort -n))"
        if [ -n "$del" ]; then
          echo "Deleting old generations: $del"
          nix-env -p "$PROFILE" --delete-generations $del
        else
          echo "Already at or below $KEEP generations."
        fi
      fi

      # Now collect garbage and optimise store
      nix-collect-garbage -d
      nix-store --optimise
    '';
  };

  # Script: flake self-update (pull from Codeberg), protect files (e.g., vars.nix)
  flakeUpdateScript = pkgs.writeShellApplication {
    name = "xoa-flake-update";
    runtimeInputs = [ pkgs.git ];
    text = ''
      set -euo pipefail
      cd "${cfg.repoDir}"

      REMOTE_URL="${cfg.flake.remoteUrl}"
      BRANCH="${cfg.flake.branch}"

      # Protect local files from being overwritten by pulls
      for p in ${lib.concatStringsSep " " (map (p: "\"${p}\"") cfg.flake.protectPaths)}; do
        if [ -e "$p" ]; then
          git update-index --skip-worktree "$p" || true
        fi
      done

      # Ensure origin points to Codeberg (or the URL you configured)
      cur="$(git remote get-url origin 2>/dev/null || true)"
      if [ -z "$cur" ]; then
        git remote add origin "$REMOTE_URL"
      elif [ "$cur" != "$REMOTE_URL" ]; then
        git remote set-url origin "$REMOTE_URL"
      fi

      git fetch --prune origin
      # Ensure we’re on the configured branch
      if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        git checkout -B "$BRANCH" "origin/$BRANCH"
      fi

      ahead="$(git rev-list --count "HEAD..origin/$BRANCH" || echo 0)"
      if [ "$ahead" -gt 0 ]; then
        echo "Pulling $ahead new commit(s) from origin/$BRANCH…"
        git merge --ff-only "origin/$BRANCH"
      else
        echo "Flake repo already up to date."
      fi
    '';
  };

  # Script: update nixpkgs input + rebuild + GC retain
  nixosUpdateScript = pkgs.writeShellApplication {
    name = "xoa-nixos-update";
    runtimeInputs = [ pkgs.git pkgs.nix pkgs.util-linux ];
    text = ''
      set -euo pipefail
      cd "${cfg.repoDir}"

      # Protect vars.nix from accidental VCS changes
      if [ -f vars.nix ]; then
        git update-index --skip-worktree vars.nix || true
      fi

      echo "Updating nixpkgs input…"
      nix flake lock --update-input nixpkgs --commit-lock-file

      HOST="${config.networking.hostName}"
      echo "Rebuilding NixOS for host: $HOST"
      nixos-rebuild switch --flake .#"$HOST" -L --show-trace

      echo "Applying GC retention (keep last ${toString cfg.nixos.keepGenerations})…"
      ${gcScript}/bin/xoa-gc-keep-last
    '';
  };

  # Script: update XO upstream input + rebuild + GC retain
  xoUpdateScript = pkgs.writeShellApplication {
    name = "xoa-xo-update";
    runtimeInputs = [ pkgs.git pkgs.nix ];
    text = ''
      set -euo pipefail
      cd "${cfg.repoDir}"

      echo "Updating xoSrc input…"
      nix flake lock --update-input xoSrc --commit-lock-file

      HOST="${config.networking.hostName}"
      echo "Rebuilding NixOS for host: $HOST"
      nixos-rebuild switch --flake .#"$HOST" -L --show-trace

      echo "Applying GC retention (keep last ${toString cfg.xoa.keepGenerations})…"
      ${gcScript}/bin/xoa-gc-keep-last
    '';
  };

in
{
  options.updates = {
    repoDir = mkOption {
      type = types.path;
      default = "/etc/nixos/declarative-xoa-ce";
      description = "Absolute path to the local git clone of this flake.";
    };

    gc = {
      enable = mkEnableOption "Automatic GC retaining only the last N successful system generations" // { default = false; };
      schedule = mkOption { type = types.str; default = "Sun 04:00"; description = "systemd OnCalendar format (e.g., \"Sun 04:00\")."; };
      keepGenerations = mkOption { type = types.int; default = 7; description = "How many successful system generations to retain."; };
    };

    nixos = {
      enable = mkEnableOption "Automatic NixOS updates (update nixpkgs input + rebuild)" // { default = false; };
      schedule = mkOption { type = types.str; default = "Sun 04:00"; };
      keepGenerations = mkOption { type = types.int; default = 7; };
    };

    flake = {
      enable = mkEnableOption "Automatic flake self-update (git pull from remote) with vars.nix protection" // { default = false; };
      schedule = mkOption { type = types.str; default = "Sun 04:00"; };
      remoteUrl = mkOption { type = types.str; default = "https://codeberg.org/dalemorgan/declarative-xoa-ce.git"; };
      branch = mkOption { type = types.str; default = "main"; };
      protectPaths = mkOption { type = types.listOf types.str; default = [ "vars.nix" ]; };
    };

    xoa = {
      enable = mkEnableOption "Automatic XO upstream updates (update xoSrc input + rebuild)" // { default = false; };
      schedule = mkOption { type = types.str; default = "Sun 04:00"; };
      keepGenerations = mkOption { type = types.int; default = 7; };
    };
  };

  config = {
    # Optional built-in optimizations when GC is enabled
    nix.optimise.automatic = mkIf cfg.gc.enable true;

    # --- Flake self-update (git pull Codeberg) ---
    systemd.services."xoa-flake-update" = mkIf cfg.flake.enable {
      description = "Flake self-update from Codeberg (protect vars.nix)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = cfg.repoDir;
        ExecStart = "${flakeUpdateScript}/bin/xoa-flake-update";
        User = "root";
      };
    };
    systemd.timers."xoa-flake-update" = mkIf cfg.flake.enable {
      description = "Weekly flake self-update (git pull)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.flake.schedule;
        Persistent = true;
      };
    };

    # --- NixOS update (update nixpkgs input + rebuild + GC retain) ---
    systemd.services."xoa-nixos-update" = mkIf cfg.nixos.enable {
      description = "Update nixpkgs input and rebuild system";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = cfg.repoDir;
        ExecStart = "${nixosUpdateScript}/bin/xoa-nixos-update";
        User = "root";
      };
    };
    systemd.timers."xoa-nixos-update" = mkIf cfg.nixos.enable {
      description = "Weekly NixOS update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.nixos.schedule;
        Persistent = true;
      };
    };

    # --- XO upstream update (update xoSrc input + rebuild + GC retain) ---
    systemd.services."xoa-xo-update" = mkIf cfg.xoa.enable {
      description = "Update xen-orchestra (xoSrc) and rebuild system";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = cfg.repoDir;
        ExecStart = "${xoUpdateScript}/bin/xoa-xo-update";
        User = "root";
      };
    };
    systemd.timers."xoa-xo-update" = mkIf cfg.xoa.enable {
      description = "Weekly XO upstream update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.xoa.schedule;
        Persistent = true;
      };
    };

    # --- Standalone GC (keep last N generations) ---
    systemd.services."xoa-gc-retain" = mkIf cfg.gc.enable {
      description = "GC with retention of last ${toString cfg.gc.keepGenerations} successful system generations";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${gcScript}/bin/xoa-gc-keep-last";
        User = "root";
      };
    };
    systemd.timers."xoa-gc-retain" = mkIf cfg.gc.enable {
      description = "Weekly GC (retain last N)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.gc.schedule;
        Persistent = true;
      };
    };
  };
}
