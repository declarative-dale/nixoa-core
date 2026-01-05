# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types optionalString;
  cfg = config.updates;

  # Get admin username from config (set by system.nix from config.nixoa.admin.username)
  adminUser = config.nixoa.admin.username or "xoa";

  # Expand tilde in repo directory path for systemd services
  expandedRepoDir = if lib.hasPrefix "~/" cfg.repoDir
    then "/home/${adminUser}/${lib.removePrefix "~/" cfg.repoDir}"
    else cfg.repoDir;

  # Common library - no Nix interpolation, no shellcheck issues
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

  # Notification helper (references config, so needs to be separate)
  mkNotificationHelper = pkgs.writeShellScript "xoa-notify.sh" ''
    send_notification() {
      local subject="$1"
      local body="$2"
      local priority="$3"

      ${optionalString cfg.monitoring.email.enable ''
        if command -v mail >/dev/null 2>&1; then
          echo "$body" | mail -s "[XOA] $subject" "${cfg.monitoring.email.to}"
        fi
      ''}

      ${optionalString cfg.monitoring.ntfy.enable ''
        if command -v curl >/dev/null 2>&1; then
          curl -H "Title: $subject" \
               -H "Priority: $priority" \
               -H "Tags: $(hostname),xoa" \
               -d "$body" \
               "${cfg.monitoring.ntfy.server}/${cfg.monitoring.ntfy.topic}" 2>/dev/null || true
        fi
      ''}

      ${optionalString cfg.monitoring.webhook.enable ''
        if command -v curl >/dev/null 2>&1; then
          curl -X POST "${cfg.monitoring.webhook.url}" \
               -H "Content-Type: application/json" \
               -d "{\"subject\":\"$subject\",\"body\":\"$body\",\"priority\":\"$priority\",\"hostname\":\"$(hostname)\"}" \
               2>/dev/null || true
        fi
      ''}
    }
  '';

  # Update specific flake input with commit comparison
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

      if [[ -n "$commit_summary" ]] || ${if cfg.monitoring.notifyOnSuccess then "true" else "false"}; then
        send_notification "$INPUT_NAME Updated" "Updated to $NEW_REV
$commit_summary" "success"
      fi
    '';
  };

  # Combined update and rebuild script
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

in
{
  options.updates = {
    repoDir = mkOption {
      type = types.str;
      default = "~/projects/NiXOA/system";
      example = "~/projects/NiXOA/system";
      description = "Path to the system flake repository directory (~ expands to admin user home)";
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
  };

  config = mkIf (cfg.autoUpgrade.enable || cfg.nixpkgs.enable || config.nixoa.xo.enable || cfg.libvhdi.enable) {
    # Enable nix-command and flakes
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Email support if enabled
    programs.msmtp.enable = mkIf cfg.monitoring.email.enable true;

    # Install helper scripts globally
    environment.systemPackages = [
      statusScript
      (updateInputScript "xoSrc")
      (updateInputScript "nixpkgs")
      (updateInputScript "libvhdiSrc")
    ];

    # Status monitoring directory
    systemd.tmpfiles.rules = [
      "d /var/lib/xoa-updates 0755 root root - -"
    ];
  };
}
