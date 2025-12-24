# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types concatStringsSep;
  cfg = config.updates;

  # Get admin username from config (set by system.nix from config.nixoa.admin.username)
  adminUser = config.nixoa.admin.username or "xoa";

  # Expand tilde in repo directory path for systemd services
  expandedRepoDir = if lib.hasPrefix "~/" cfg.repoDir
    then "/home/${adminUser}/${lib.removePrefix "~/" cfg.repoDir}"
    else cfg.repoDir;

  # Common script utilities - reusable functions
  commonUtils = ''
    log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"; }
    log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
    log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*"; }
    
    ensure_repo_dir() {
      if [[ ! -d "${expandedRepoDir}" ]]; then
        log_error "Repository directory not found: ${expandedRepoDir}"
        exit 1
      fi
      cd "${expandedRepoDir}"
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
    # shellcheck disable=SC2034
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
      
      log_info "Starting garbage collection (keeping ${toString cfg.gc.keepGenerations} generations)"
      write_status "gc" "running" "Starting garbage collection"
      
      # Get current generation
      current_gen=$(readlink /nix/var/nix/profiles/system | sed 's/.*-\([0-9]*\)-link$/\1/')
      log_info "Current system generation: $current_gen"

      # List all system generations
      all_gens=$(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' -type l 2>/dev/null | sed 's/.*-\([0-9]*\)-link$/\1/' | sort -nr)

      # Keep only the specified number of generations
      keep_count=0
      for gen in $all_gens; do
        if [[ $keep_count -lt ${toString cfg.gc.keepGenerations} ]]; then
          log_info "Keeping generation $gen"
          keep_count=$((keep_count + 1))
        else
          if [[ $gen != "$current_gen" ]]; then
            log_info "Removing generation $gen"
            nix-env -p /nix/var/nix/profiles/system --delete-generations "$gen" 2>/dev/null || true
          fi
        fi
      done
      
      # Run garbage collection
      log_info "Running nix-collect-garbage..."
      if nix-collect-garbage -d; then
        log_success "Garbage collection completed"
        write_status "gc" "success" "Completed successfully"
        
        # Report disk space saved
        df -h /nix/store | tail -1
      else
        log_error "Garbage collection failed"
        write_status "gc" "failed" "GC failed"
        exit 1
      fi
    '';
  };

  # Script to check all statuses
  statusScript = pkgs.writeShellApplication {
    name = "xoa-update-status";
    runtimeInputs = with pkgs; [ coreutils jq ];
    text = ''
      STATUS_DIR="/var/lib/xoa-updates"
      
      if [[ ! -d "$STATUS_DIR" ]]; then
        echo "No status information available"
        exit 0
      fi
      
      echo "=== XOA Update System Status ==="
      echo ""
      
      for status_file in "$STATUS_DIR"/*.status; do
        if [[ -f "$status_file" ]]; then
          service=$(jq -r '.service' "$status_file")
          status=$(jq -r '.status' "$status_file")
          message=$(jq -r '.message' "$status_file")
          timestamp=$(jq -r '.timestamp' "$status_file")
          
          printf "%-20s %-10s %-40s %s\n" "$service" "$status" "$message" "$timestamp"
        fi
      done
    '';
  };

  # Flake self-update script (pull from git)
  flakeUpdateScript = pkgs.writeShellApplication {
    name = "xoa-flake-update";
    runtimeInputs = with pkgs; [ git ];
    text = ''
      ${commonUtils}

      ensure_repo_dir

      REMOTE="${cfg.flake.remoteUrl}"
      BRANCH="${cfg.flake.branch}"
      
      log_info "Updating flake from $REMOTE ($BRANCH)"
      write_status "flake-update" "running" "Pulling from $REMOTE"
      
      # Configure remote if not exists
      if ! git remote | grep -q "^upstream$"; then
        log_info "Adding upstream remote: $REMOTE"
        git remote add upstream "$REMOTE"
      else
        git remote set-url upstream "$REMOTE"
      fi
      
      # Fetch latest
      if ! git fetch upstream "$BRANCH"; then
        log_error "Failed to fetch from upstream"
        write_status "flake-update" "failed" "Fetch failed"
        send_notification "Flake Update Failed" "Could not fetch from $REMOTE" "error"
        exit 1
      fi
      
      # Check if we're behind
      LOCAL=$(git rev-parse HEAD)
      REMOTE_REF=$(git rev-parse "upstream/$BRANCH")
      
      if [[ "$LOCAL" == "$REMOTE_REF" ]]; then
        log_info "Already up to date"
        write_status "flake-update" "success" "Already up to date"
        exit 0
      fi
      
      # Count commits behind
      behind=$(git rev-list --count "HEAD..upstream/$BRANCH")
      log_info "Pulling $behind new commit(s)"
      
      # Get commit messages
      commit_msgs=$(git log --oneline "HEAD..upstream/$BRANCH" | head -5)
      
      if git merge --ff-only "upstream/$BRANCH"; then
        log_success "Flake updated successfully ($behind commits)"
        write_status "flake-update" "success" "Updated $behind commits"
        send_notification "Flake Updated" "Pulled $behind new commit(s):
$commit_msgs" "success"
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
        elif [[ "${inputName}" == "libvhdiSrc" ]]; then
          commit_summary="Updated libvhdi from $OLD_REV to $NEW_REV"
        fi
      fi
      
      log_success "${inputName} input updated"
      write_status "${inputName}-update" "success" "Updated to $NEW_REV"
      
      if [[ -n "$commit_summary" ]] || ${if cfg.monitoring.notifyOnSuccess then "true" else "false"}; then
        send_notification "${inputName} Updated" "Updated to $NEW_REV
$commit_summary" "success"
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

in
{
  options.updates = {
    repoDir = mkOption {
      type = types.str;
      default = "~/user-config";
      example = "~/user-config";
      description = "Path to the user-config flake repository directory (~ expands to admin user home)";
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
        default = "https://codeberg.org/nixoa/nixoa-vm.git";
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

    libvhdi = {
      enable = mkEnableOption "Automatic libvhdi source updates";
      schedule = mkOption {
        type = types.str;
        default = "Wed 04:00";
        description = "When to update libvhdi";
      };
      keepGenerations = mkOption {
        type = types.int;
        default = 7;
        description = "Generations to keep after update";
      };
    };
  };

  config = mkIf (cfg.gc.enable || cfg.flake.enable || cfg.nixpkgs.enable || cfg.xoa.enable || cfg.libvhdi.enable) {
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
      (updateInputScript "libvhdiSrc")
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
        WorkingDirectory = expandedRepoDir;
        ExecStart = "${flakeUpdateScript}/bin/xoa-flake-update";
        User = "root";
      } // (if cfg.flake.autoRebuild then {
        ExecStartPost = "${pkgs.writeShellScript "rebuild-after-flake-update" ''
          cd ${expandedRepoDir}
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
        WorkingDirectory = expandedRepoDir;
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
        WorkingDirectory = expandedRepoDir;
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

    # --- libvhdi Update ---
    systemd.services."xoa-libvhdi-update" = mkIf cfg.libvhdi.enable {
      description = "XOA libvhdi Update and Rebuild";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = expandedRepoDir;
        ExecStart = "${updateAndRebuildScript "libvhdiSrc" cfg.libvhdi.keepGenerations}/bin/xoa-update-libvhdiSrc-rebuild";
        User = "root";
        TimeoutStartSec = "30min";
      };
    };

    systemd.timers."xoa-libvhdi-update" = mkIf cfg.libvhdi.enable {
      description = "XOA libvhdi Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.libvhdi.schedule;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };
  };
}
