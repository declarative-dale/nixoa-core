# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.updates.libvhdi;

  # Import common utilities - these are defined in common.nix let block
  # We need to re-import and re-compute them here since they're needed for service config
  adminUser = config.nixoa.admin.username or "xoa";
  expandedRepoDir = if lib.hasPrefix "~/" config.updates.repoDir
    then "/home/${adminUser}/${lib.removePrefix "~/" config.updates.repoDir}"
    else config.updates.repoDir;

  # Re-define the scripts needed for this module
  xoaCommonLib = pkgs.writeShellScript "xoa-lib.sh" ''
    log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"; }
    log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
    log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*"; }

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
      "hostname": "$(hostname)"
    }
    EOF
    }
  '';

  mkNotificationHelper = pkgs.writeShellScript "xoa-notify.sh" ''
    send_notification() {
      local subject="$1"
      local body="$2"
      local priority="$3"

      ${lib.optionalString config.updates.monitoring.email.enable ''
        if command -v mail >/dev/null 2>&1; then
          echo "$body" | mail -s "[XOA] $subject" "${config.updates.monitoring.email.to}"
        fi
      ''}

      ${lib.optionalString config.updates.monitoring.ntfy.enable ''
        if command -v curl >/dev/null 2>&1; then
          curl -H "Title: $subject" \
               -H "Priority: $priority" \
               -H "Tags: $(hostname),xoa" \
               -d "$body" \
               "${config.updates.monitoring.ntfy.server}/${config.updates.monitoring.ntfy.topic}" 2>/dev/null || true
        fi
      ''}

      ${lib.optionalString config.updates.monitoring.webhook.enable ''
        if command -v curl >/dev/null 2>&1; then
          curl -X POST "${config.updates.monitoring.webhook.url}" \
               -H "Content-Type: application/json" \
               -d "{\"subject\":\"$subject\",\"body\":\"$body\",\"priority\":\"$priority\",\"hostname\":\"$(hostname)\"}" \
               2>/dev/null || true
        fi
      ''}
    }
  '';

  updateInputScript = inputName: pkgs.writeShellApplication {
    name = "xoa-update-${inputName}";
    runtimeInputs = with pkgs; [ git nix jq curl ];
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${xoaCommonLib}
      source ${mkNotificationHelper}

      REPO_DIR="${expandedRepoDir}"
      INPUT_NAME="${inputName}"

      cd "$REPO_DIR"

      log_info "Updating $INPUT_NAME input..."
      write_status "$INPUT_NAME-update" "running" "Updating $INPUT_NAME input"

      # Get current rev
      OLD_REV=$(jq -r '.nodes.$INPUT_NAME.locked.rev // empty' flake.lock 2>/dev/null || echo "")

      # Update the input
      if ! nix flake lock --update-input $INPUT_NAME --commit-lock-file; then
        log_error "Failed to update $INPUT_NAME input"
        write_status "$INPUT_NAME-update" "failed" "Flake lock failed"
        send_notification "$INPUT_NAME Update Failed" "Failed to update flake input" "error"
        exit 1
      fi

      # Get new rev
      NEW_REV=$(jq -r '.nodes.$INPUT_NAME.locked.rev // empty' flake.lock)

      if [[ -z "$NEW_REV" ]]; then
        log_error "Could not read new revision from flake.lock"
        write_status "$INPUT_NAME-update" "failed" "Invalid flake.lock"
        send_notification "$INPUT_NAME Update Failed" "Could not read new revision" "error"
        exit 1
      fi

      if [[ "$OLD_REV" == "$NEW_REV" ]]; then
        log_info "$INPUT_NAME already up to date"
        write_status "$INPUT_NAME-update" "success" "Already up to date"
        exit 0
      fi

      log_info "$INPUT_NAME: ''${OLD_REV:-none} -> $NEW_REV"

      # Show commits if both revisions exist
      commit_summary=""
      if [[ -n "$OLD_REV" && "$OLD_REV" != "$NEW_REV" ]]; then
        log_info "Fetching commit history..."

        # For GitHub repos, try API first
        if [[ "$INPUT_NAME" == "xoSrc" ]]; then
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
        elif [[ "$INPUT_NAME" == "nixpkgs" ]]; then
          commit_summary="Updated nixpkgs from $OLD_REV to $NEW_REV"
        elif [[ "$INPUT_NAME" == "libvhdiSrc" ]]; then
          commit_summary="Updated libvhdi from $OLD_REV to $NEW_REV"
        fi
      fi

      log_success "$INPUT_NAME input updated"
      write_status "$INPUT_NAME-update" "success" "Updated to $NEW_REV"

      if [[ -n "$commit_summary" ]] || ${if config.updates.monitoring.notifyOnSuccess then "true" else "false"}; then
        send_notification "$INPUT_NAME Updated" "Updated to $NEW_REV
$commit_summary" "success"
      fi
    '';
  };

  updateAndRebuildScript = inputName: pkgs.writeShellApplication {
    name = "xoa-update-${inputName}-rebuild";
    runtimeInputs = with pkgs; [ git nix ];
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${xoaCommonLib}
      source ${mkNotificationHelper}

      REPO_DIR="${expandedRepoDir}"
      HOSTNAME="${config.networking.hostName}"
      INPUT_NAME="${inputName}"

      cd "$REPO_DIR"

      log_info "Starting $INPUT_NAME update and rebuild"
      write_status "$INPUT_NAME-rebuild" "running" "Starting update and rebuild"

      start_time=$(date +%s)

      # Update the input
      if ! ${updateInputScript inputName}/bin/xoa-update-$INPUT_NAME; then
        log_error "Input update failed"
        write_status "$INPUT_NAME-rebuild" "failed" "Input update failed"
        send_notification "$INPUT_NAME Rebuild Failed" "Failed to update $INPUT_NAME input" "error"
        exit 1
      fi

      # Rebuild system
      log_info "Rebuilding NixOS configuration for host: $HOSTNAME"
      if nixos-rebuild switch --flake ".#$HOSTNAME" -L; then
        log_success "System rebuild completed"
      else
        log_error "System rebuild failed"
        write_status "$INPUT_NAME-rebuild" "failed" "System rebuild failed"
        send_notification "$INPUT_NAME Rebuild Failed" "NixOS rebuild failed - system may need manual intervention" "error"
        exit 1
      fi

      end_time=$(date +%s)
      duration=$((end_time - start_time))

      log_success "Update completed successfully in ''${duration}s"
      write_status "$INPUT_NAME-rebuild" "success" "Completed in ''${duration}s"
      send_notification "$INPUT_NAME Rebuild Successful" "System updated and rebuilt successfully in ''${duration}s" "success"
    '';
  };

in
{
  options.updates.libvhdi = {
    enable = mkEnableOption "Automatic libvhdi source updates";
    schedule = mkOption {
      type = types.str;
      default = "Wed 04:00";
      description = "When to update libvhdi";
    };
  };

  config = mkIf cfg.enable {
    # --- libvhdi Update ---
    systemd.services."xoa-libvhdi-update" = {
      description = "XOA libvhdi Update and Rebuild";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = expandedRepoDir;
        ExecStart = "${updateAndRebuildScript "libvhdiSrc"}/bin/xoa-update-libvhdiSrc-rebuild";
        User = "root";
        TimeoutStartSec = "30min";
      };
    };

    systemd.timers."xoa-libvhdi-update" = {
      description = "XOA libvhdi Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };
  };
}
