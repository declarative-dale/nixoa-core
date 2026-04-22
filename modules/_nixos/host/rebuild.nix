# SPDX-License-Identifier: Apache-2.0
# Rebuild the host once on the next boot if the TUI has queued it.
{ ... }:
let
  queueFile = "/var/lib/nixoa/rebuild-on-boot.env";
in
{
  systemd.services.nixoa-rebuild = {
    description = "Apply queued NiXOA rebuild on boot";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = queueFile;
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail

      queue_file='${queueFile}'
      # shellcheck source=/var/lib/nixoa/rebuild-on-boot.env
      . "$queue_file"

      if [ -z "''${repo_root:-}" ] || [ -z "''${hostname:-}" ]; then
        echo "Queued NiXOA rebuild is missing repo_root or hostname." >&2
        exit 1
      fi

      "$repo_root/scripts/apply-config.sh" --hostname "$hostname"
      rm -f "$queue_file"
    '';
  };
}
