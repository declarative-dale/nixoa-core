# SPDX-License-Identifier: Apache-2.0
# Keep DBus broker stable across appliance switches.
{lib, ...}: {
  systemd.services.dbus-broker = {
    reloadIfChanged = lib.mkForce false;
    restartIfChanged = lib.mkForce false;
  };
}
