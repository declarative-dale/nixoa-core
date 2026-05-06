# SPDX-License-Identifier: Apache-2.0
# Per-host Flatpak enablement and app synchronization
{
  lib,
  pkgs,
  context,
  ...
}:
let
  flatpaks = context.flatpaks or [ ];
  remotes = context.flatpakRemotes or [ ];
  enabled = flatpaks != [ ];
  remoteCommands = lib.concatMapStringsSep "\n" (
    remote:
    ''
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists ${lib.escapeShellArg remote.name} ${lib.escapeShellArg remote.location}
    ''
  ) remotes;
  appCommands = lib.concatMapStringsSep "\n" (
    appId:
    ''
      if ! ${pkgs.flatpak}/bin/flatpak info --system ${lib.escapeShellArg appId} >/dev/null 2>&1; then
        ${pkgs.flatpak}/bin/flatpak install --system --assumeyes --noninteractive flathub ${lib.escapeShellArg appId}
      fi
    ''
  ) flatpaks;
in
{
  config = lib.mkIf enabled {
    services.flatpak.enable = true;
    xdg.portal.enable = true;

    environment.etc."nixoa/flatpaks.json".text = builtins.toJSON {
      inherit flatpaks remotes;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/flatpak 0755 root root - -"
    ];

    systemd.services.nixoa-flatpak-sync = {
      description = "Synchronize configured NiXOA Flatpaks";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "dbus.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -euo pipefail

        ${remoteCommands}
        ${appCommands}
      '';
    };

    assertions = [
      {
        assertion = remotes != [ ];
        message = "NiXOA flatpaks are configured, but no flatpakRemotes were provided.";
      }
      {
        assertion = builtins.any (remote: remote.name == "flathub") remotes;
        message = "NiXOA flatpak synchronization currently expects a flatpakRemotes entry named 'flathub'.";
      }
    ];
  };
}
