# SPDX-License-Identifier: Apache-2.0
# System state version
{
  vars,
  ...
}:
{
  # DO NOT CHANGE after initial installation
  system.stateVersion = vars.stateVersion;
}
