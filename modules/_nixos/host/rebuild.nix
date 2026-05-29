# SPDX-License-Identifier: Apache-2.0
# Rebuild the host once on the next boot if the TUI has queued it.
{
  inputs,
  pkgs,
  ...
}: let
  queueFile = "/var/lib/nixoa/rebuild-on-boot.env";
  nxcli = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.nxcli;
in {
  systemd.tmpfiles.rules = [
    "d /var/lib/nixoa 0750 root root - -"
  ];

  systemd.services.nixoa-rebuild = {
    description = "Apply queued NiXOA rebuild on boot";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
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

      rebuild_target="''${target:-''${hostname:-}}"

      if [ -z "''${repo_root:-}" ] || [ -z "$rebuild_target" ]; then
        echo "Queued NiXOA rebuild is missing repo_root or target." >&2
        exit 1
      fi

      NIXOA_SYSTEM_ROOT="$repo_root" "${nxcli}/bin/nxcli" apply --target "$rebuild_target"
      rm -f "$queue_file"
    '';
  };
}
