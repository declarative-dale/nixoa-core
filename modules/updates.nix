{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types concatStringsSep;
  cfg = config.updates;

  # Common script utilities - reusable functions
  commonUtils = ''
    log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"; }
    log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
    log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*"; }
    
    ensure_repo_dir() {
      if [[ ! -d "${cfg.repoDir}" ]]; then
        log_error "Repository directory not found: ${cfg.repoDir}"
        exit 1
      fi
      cd "${cfg.repoDir}"
    }
    
    protect_local_files() {
      for p in ${concatStringsSep " " (map (p: "\"${p}\"") cfg.protectPaths)}; do
        if [[ -e "$p" ]]; then
          git update-index --skip-worktree "$p" 2>/dev/null || true
          log_info "Protected: $p"
        fi
      done
    }
    
    rebuild_system() {
      local host="${config.networking.hostName}"
      log_info "Rebuilding NixOS configuration for host: $host"
      if nixos-rebuild switch --flake .#"$host" -L; then
        log_success "System rebuild completed"
        return 0
      else
        log_error "System rebuild failed"
        return 1
      fi
    }
    
    # Write status to monitoring file
    write_status() {
      local service="$1"
      local status="$2"
      local message="$3"
      local timestamp
      timestamp=$(date -Iseconds)
      
      mkdir -p /var/lib/xoa-updates
      cat > "/var/lib/xoa-updates/$service.status" <<EOF
    {
      "service": "$service",
      "status": "$status",
      "message": "$message",
      "timestamp": "$timestamp",
      "hostname": "${config.networking.hostName}"
    }
    EOF
    }
    
    # Send notification if configured
    send_notification() {
      local subject="$1"
      local body="$2"
      local priority="$3"  # success, warning, error
      
      ${if cfg.monitoring.email.enable then ''
        if command -v mail >/dev/null 2>&1; then
          echo "$body" | mail -s "[XOA] $subject" "${cfg.monitoring.email.to}"
        fi
      '' else ""}
      
      ${if cfg.monitoring.ntfy.enable then ''
        if command -v curl >/dev/null 2>&1; then
          curl -H "Title: $subject" \
               -H "Priority: $priority" \
               -H "Tags: ${config.networking.hostName},xoa" \
               -d "$body" \
               "${cfg.monitoring.ntfy.server}/${cfg.monitoring.ntfy.topic}" 2>/dev/null || true
        fi
      '' else ""}
      
      ${if cfg.monitoring.webhook.enable then ''
        if command -v curl >/dev/null 2>&1; then
          curl -X POST "${cfg.monitoring.webhook.url}" \
               -H "Content-Type: application/json" \
               -d "{\"subject\":\"$subject\",\"body\":\"$body\",\"priority\":\"$priority\",\"hostname\":\"${config.networking.hostName}\"}" \
               2>/dev/null || true
        fi
      '' else ""}
    }
  '';

  # GC script with proper generation management
  gcScript = pkgs.writeShellApplication {
    name = "xoa-gc-generations";
    runtimeInputs = with pkgs; [ coreutils gnugrep gawk nix ];
    text = ''
      ${commonUtils}
      
      KEEP="${toString cfg.gc.keepGenerations}"
      PROFILE="/nix/var/nix/profiles/system"
      
      log_info "Running GC, keeping last $KEEP successful generations"
      write_status "gc" "running" "Starting garbage collection"
      
      # Get all generations
      if ! generations=$(nix-env -p "$PROFILE" --list-generations 2>/dev/null); then
        log_error "Failed to list generations"
        write_status "gc" "failed" "Could not list generations"
        send_notification "GC Failed" "Failed to list system generations" "error"
        exit 1
      fi
      
      # Extract generation numbers
      gen_numbers=$(echo "$generations" | awk '{print $1}' | sort -n)
      total=$(echo "$gen_numbers" | wc -l)
      
      deleted_count=0
      if [[ $total -le $KEEP ]]; then
        log_info "Only $total generation(s) exist, keeping all"
      else
        # Keep last N, delete the rest
        to_keep=$(echo "$gen_numbers" | tail -n "$KEEP")
        to_delete=$(comm -23 <(echo "$gen_numbers") <(echo "$to_keep"))
        
        if [[ -n "$to_delete" ]]; then
          deleted_count=$(echo "$to_delete" | wc -w)
          log_info "Deleting $deleted_count generation(s): $(echo $to_delete | tr '\n' ' ')"
          # shellcheck disable=SC2086
          nix-env -p "$PROFILE" --delete-generations $to_delete
        fi
      fi
      
      log_info "Collecting garbage..."
      gc_output=$(nix-collect-garbage -d 2>&1 || true)
      freed=$(echo "$gc_output" | grep -oP '\d+\.\d+ MiB' | head -1 || echo "unknown")
      
      log_info "Optimizing store..."
      nix-store --optimise
      
      log_success "GC completed: deleted $deleted_count generations, freed $freed"
      write_status "gc" "success" "Deleted $deleted_count generations, freed $freed"
      
      if [[ $deleted_count -gt 0 ]] || ${if cfg.monitoring.notifyOnSuccess then "true" else "false"}; then
        send_notification "GC Completed" "Deleted $deleted_count generations, freed $freed" "success"
      fi
    '';
  };

  # Flake self-update (pull from remote)
  flakeUpdateScript = pkgs.writeShellApplication {
    name = "xoa-flake-update";
    runtimeInputs = with pkgs; [ git coreutils ];
    text = ''
      ${commonUtils}
      
      ensure_repo_dir
      protect_local_files
      
      REMOTE_URL="${cfg.flake.remoteUrl}"
      BRANCH="${cfg.flake.branch}"
      
      log_info "Updating flake from remote: $REMOTE_URL (branch: $BRANCH)"
      write_status "flake-update" "running" "Checking for flake updates"
      
      # Ensure remote is configured correctly
      if current_url=$(git remote get-url origin 2>/dev/null); then
        if [[ "$current_url" != "$REMOTE_URL" ]]; then
          log_info "Updating remote URL"
          git remote set-url origin "$REMOTE_URL"
        fi
      else
        log_info "Adding remote origin"
        git remote add origin "$REMOTE_URL"
      fi
      
      # Fetch latest
      if ! git fetch --prune origin; then
        log_error "Failed to fetch from remote"
        write_status "flake-update" "failed" "Git fetch failed"
        send_notification "Flake Update Failed" "Failed to fetch from $REMOTE_URL" "error"
        exit 1
      fi
      
      # Check if on correct branch
      current_branch=$(git rev-parse --abbrev-ref HEAD)
      if [[ "$current_branch" != "$BRANCH" ]]; then
        log_info "Switching to branch: $BRANCH"
        git checkout -B "$BRANCH" "origin/$BRANCH"
      fi
      
      # Check for updates
      LOCAL=$(git rev-parse HEAD)
      REMOTE=$(git rev-parse "origin/$BRANCH")
      
      if [[ "$LOCAL" == "$REMOTE" ]]; then
        log_info "Flake already up to date"
        write_status "flake-update" "success" "Already up to date"
        exit 0
      fi
      
      # Count commits behind
      behind=$(git rev-list --count "HEAD..origin/$BRANCH")
      log_info "Pulling $behind new commit(s)"
      
      # Get commit messages
      commit_msgs=$(git log --oneline "HEAD..origin/$BRANCH" | head -5)
      
      if git merge --ff-only "origin/$BRANCH"; then
        log_success "Flake updated successfully ($behind commits)"
        write_status "flake-update" "success" "Updated $behind commits"
        send_notification "Flake Updated" "Pulled $behind new commit(s):\n$commit_msgs" "success"
      else
        log_error "Failed to merge (conflicts?)"
        write_status "flake-update" "failed" "Merge conflict"
        send_notification "Flake Update Failed" "Merge conflicts detected" "error"
        exit 1
      fi
    '';
  };

  # Update specific flake input with commit comparison
  updateInputScript = inputName: pkgs.writeShellApplication {
    name = "xoa-update-${inputName}";
    runtimeInputs = with pkgs; [ git nix jq curl ];
    text = ''
      ${commonUtils}
      
      ensure_repo_dir
      protect_local_files
      
      log_info "Updating ${inputName} input..."
      write_status "${inputName}-update" "running" "Updating ${inputName} input"
      
      # Get current rev
      OLD_REV=$(jq -r '.nodes.${inputName}.locked.rev // empty' flake.lock 2>/dev/null || echo "")
      
      # Update the input
      if ! nix flake lock --update-input ${inputName} --commit-lock-file; then
        log_error "Failed to update ${inputName} input"
        write_status "${inputName}-update" "failed" "Flake lock failed"
        send_notification "${inputName} Update Failed" "Failed to update flake input" "error"
        exit 1
      fi
      
      # Get new rev
      NEW_REV=$(jq -r '.nodes.${inputName}.locked.rev // empty' flake.lock)
      
      if [[ -z "$NEW_REV" ]]; then
        log_error "Could not read new revision from flake.lock"
        write_status "${inputName}-update" "failed" "Invalid flake.lock"
        send_notification "${inputName} Update Failed" "Could not read new revision" "error"
        exit 1
      fi
      
      if [[ "$OLD_REV" == "$NEW_REV" ]]; then
        log_info "${inputName} already up to date"
        write_status "${inputName}-update" "success" "Already up to date"
        exit 0
      fi
      
      log_info "${inputName}: ''${OLD_REV:-none} -> $NEW_REV"
      
      # Show commits if both revisions exist
      commit_summary=""
      if [[ -n "$OLD_REV" && "$OLD_REV" != "$NEW_REV" ]]; then
        log_info "Fetching commit history..."
        
        # For GitHub repos, try API first
        if [[ "${inputName}" == "xoSrc" ]]; then
          API_URL="https://api.github.com/repos/vatesfr/xen-orchestra/compare/$OLD_REV...$NEW_REV"
          
          if response=$(curl -s "$API_URL" 2>/dev/null); then
            commit_count=$(echo "$response" | jq -r '.total_commits // 0' 2>/dev/null || echo "0")
            if [[ "$commit_count" != "0" ]]; then
              commit_summary=$(echo "$response" | jq -r '.commits[]? | "  \(.sha[0:7]) \(.commit.message | split("\n")[0])"' 2>/dev/null | head -5 || echo "")
              if [[ -n "$commit_summary" ]]; then
                echo "Changes ($commit_count commits):"
                echo "$commit_summary"
              fi
            fi
          fi
        elif [[ "${inputName}" == "nixpkgs" ]]; then
          commit_summary="Updated nixpkgs from $OLD_REV to $NEW_REV"
        fi
      fi
      
      log_success "${inputName} input updated"
      write_status "${inputName}-update" "success" "Updated to $NEW_REV"
      
      if [[ -n "$commit_summary" ]] || ${if cfg.monitoring.notifyOnSuccess then "true" else "false"}; then
        send_notification "${inputName} Updated" "Updated to $NEW_REV\n$commit_summary" "success"
      fi
    '';
  };

  # Combined update and rebuild script
  updateAndRebuildScript = inputName: keepGens: pkgs.writeShellApplication {
    name = "xoa-update-${inputName}-rebuild";
    runtimeInputs = with pkgs; [ git nix ];
    text = ''
      ${commonUtils}
      
      ensure_repo_dir
      
      log_info "Starting ${inputName} update and rebuild"
      write_status "${inputName}-rebuild" "running" "Starting update and rebuild"
      
      start_time=$(date +%s)
      
      # Update the input
      if ! ${updateInputScript inputName}/bin/xoa-update-${inputName}; then
        log_error "Input update failed"
        write_status "${inputName}-rebuild" "failed" "Input update failed"
        send_notification "${inputName} Rebuild Failed" "Failed to update ${inputName} input" "error"
        exit 1
      fi
      
      # Rebuild system
      if ! rebuild_system; then
        log_error "System rebuild failed"
        write_status "${inputName}-rebuild" "failed" "System rebuild failed"
        send_notification "${inputName} Rebuild Failed" "NixOS rebuild failed - system may need manual intervention" "error"
        exit 1
      fi
      
      # Run GC if configured
      ${if keepGens > 0 then ''
        log_info "Running garbage collection (keeping ${toString keepGens} generations)"
        if ! ${gcScript}/bin/xoa-gc-generations; then
          log_error "GC failed (non-fatal)"
        fi
      '' else ""}
      
      end_time=$(date +%s)
      duration=$((end_time - start_time))
      
      log_success "Update completed successfully in ''${duration}s"
      write_status "${inputName}-rebuild" "success" "Completed in ''${duration}s"
      send_notification "${inputName} Rebuild Successful" "System updated and rebuilt successfully in ''${duration}s" "success"
    '';
  };

  # Status monitoring script
  statusScript = pkgs.writeShellApplication {
    name = "xoa-update-status";
    runtimeInputs = with pkgs; [ coreutils jq ];
    text = ''
      STATUS_DIR="/var/lib/xoa-updates"
      
      if [[ ! -d "$STATUS_DIR" ]]; then
        echo "No update status available yet"
        exit 0
      fi
      
      echo "=== XOA Update Status ==="
      echo
      
      for status_file in "$STATUS_DIR"/*.status; do
        if [[ -f "$status_file" ]]; then
          service=$(jq -r '.service' "$status_file")
          status=$(jq -r '.status' "$status_file")
          message=$(jq -r '.message' "$status_file")
          timestamp=$(jq -r '.timestamp' "$status_file")
          
          # Color output based on status
          case "$status" in
            success) color="\033[0;32m" ;;  # green
            failed)  color="\033[0;31m" ;;  # red
            running) color="\033[0;33m" ;;  # yellow
            *)       color="\033[0m" ;;     # default
          esac
          
          echo -e "''${color}[$status]''${color}\033[0m $service"
          echo "  Time: $timestamp"
          echo "  Info: $message"
          echo
        fi
      done
      
      # Show next scheduled runs
      echo "=== Next Scheduled Updates ==="
      systemctl list-timers 'xoa-*' --no-pager
    '';
  };

in
{
  options.updates = {
    repoDir = mkOption {
      type = types.path;
      default = "/etc/nixos/declarative-xoa-ce";
      description = "Absolute path to the flake repository";
    };

    protectPaths = mkOption {
      type = types.listOf types.str;
      default = [ "vars.nix" "hardware-configuration.nix" ];
      description = "Files to protect from git operations (skip-worktree)";
    };

    monitoring = {
      notifyOnSuccess = mkOption {
        type = types.bool;
        default = false;
        description = "Send notifications for successful updates (not just failures)";
      };

      email = {
        enable = mkEnableOption "Email notifications for updates";
        to = mkOption {
          type = types.str;
          default = "root@localhost";
          description = "Email address for notifications";
        };
      };

      ntfy = {
        enable = mkEnableOption "ntfy.sh push notifications";
        server = mkOption {
          type = types.str;
          default = "https://ntfy.sh";
          description = "ntfy server URL";
        };
        topic = mkOption {
          type = types.str;
          default = "xoa-updates";
          description = "ntfy topic name";
        };
      };

      webhook = {
        enable = mkEnableOption "Generic webhook notifications";
        url = mkOption {
          type = types.str;
          default = "";
          description = "Webhook URL for notifications";
        };
      };
    };

    gc = {
      enable = mkEnableOption "Automatic garbage collection with generation retention";
      schedule = mkOption {
        type = types.str;
        default = "Sun 04:00";
        description = "When to run GC (systemd calendar format)";
      };
      keepGenerations = mkOption {
        type = types.int;
        default = 7;
        description = "Number of successful system generations to keep";
      };
    };

    flake = {
      enable = mkEnableOption "Automatic flake self-update from git remote";
      schedule = mkOption {
        type = types.str;
        default = "Sun 04:00";
        description = "When to check for flake updates";
      };
      remoteUrl = mkOption {
        type = types.str;
        default = "https://codeberg.org/dalemorgan/declarative-xoa-ce.git";
        description = "Git remote URL for flake updates";
      };
      branch = mkOption {
        type = types.str;
        default = "main";
        description = "Git branch to track";
      };
      autoRebuild = mkOption {
        type = types.bool;
        default = false;
        description = "Automatically rebuild after pulling changes";
      };
    };

    nixpkgs = {
      enable = mkEnableOption "Automatic nixpkgs input updates";
      schedule = mkOption {
        type = types.str;
        default = "Mon 04:00";
        description = "When to update nixpkgs";
      };
      keepGenerations = mkOption {
        type = types.int;
        default = 7;
        description = "Generations to keep after update";
      };
    };

    xoa = {
      enable = mkEnableOption "Automatic Xen Orchestra upstream updates";
      schedule = mkOption {
        type = types.str;
        default = "Tue 04:00";
        description = "When to update XO";
      };
      keepGenerations = mkOption {
        type = types.int;
        default = 7;
        description = "Generations to keep after update";
      };
    };
  };

  config = mkIf (cfg.gc.enable || cfg.flake.enable || cfg.nixpkgs.enable || cfg.xoa.enable) {
    # Enable nix-command and flakes
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    
    # Optional automatic store optimization
    nix.optimise.automatic = mkIf cfg.gc.enable true;

    # Email support if enabled
    programs.msmtp.enable = mkIf cfg.monitoring.email.enable true;

    # Install helper scripts globally
    environment.systemPackages = [
      gcScript
      flakeUpdateScript
      statusScript
      (updateInputScript "xoSrc")
      (updateInputScript "nixpkgs")
    ];

    # Status monitoring directory
    systemd.tmpfiles.rules = [
      "d /var/lib/xoa-updates 0755 root root - -"
    ];

    # --- Standalone GC Timer ---
    systemd.services."xoa-gc" = mkIf cfg.gc.enable {
      description = "XOA Garbage Collection (keep last ${toString cfg.gc.keepGenerations} generations)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${gcScript}/bin/xoa-gc-generations";
        User = "root";
      };
    };

    systemd.timers."xoa-gc" = mkIf cfg.gc.enable {
      description = "XOA Garbage Collection Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.gc.schedule;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };

    # --- Flake Self-Update ---
    systemd.services."xoa-flake-update" = mkIf cfg.flake.enable {
      description = "XOA Flake Self-Update";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = cfg.repoDir;
        ExecStart = "${flakeUpdateScript}/bin/xoa-flake-update";
        User = "root";
      } // (if cfg.flake.autoRebuild then {
        ExecStartPost = "${pkgs.writeShellScript "rebuild-after-flake-update" ''
          cd ${cfg.repoDir}
          nixos-rebuild switch --flake .#${config.networking.hostName} -L
        ''}";
      } else {});
    };

    systemd.timers."xoa-flake-update" = mkIf cfg.flake.enable {
      description = "XOA Flake Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.flake.schedule;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };

    # --- NixOS (nixpkgs input) Update ---
    systemd.services."xoa-nixpkgs-update" = mkIf cfg.nixpkgs.enable {
      description = "XOA NixOS/nixpkgs Update and Rebuild";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = cfg.repoDir;
        ExecStart = "${updateAndRebuildScript "nixpkgs" cfg.nixpkgs.keepGenerations}/bin/xoa-update-nixpkgs-rebuild";
        User = "root";
        TimeoutStartSec = "30min";
      };
    };

    systemd.timers."xoa-nixpkgs-update" = mkIf cfg.nixpkgs.enable {
      description = "XOA NixOS Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.nixpkgs.schedule;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };

    # --- XO Upstream Update ---
    systemd.services."xoa-xo-update" = mkIf cfg.xoa.enable {
      description = "XOA Xen Orchestra Upstream Update and Rebuild";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = cfg.repoDir;
        ExecStart = "${updateAndRebuildScript "xoSrc" cfg.xoa.keepGenerations}/bin/xoa-update-xoSrc-rebuild";
        User = "root";
        TimeoutStartSec = "30min";
      };
    };

    systemd.timers."xoa-xo-update" = mkIf cfg.xoa.enable {
      description = "XOA XO Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.xoa.schedule;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };
  };
}