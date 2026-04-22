# SPDX-License-Identifier: Apache-2.0
# Host state version
{
  context,
  ...
}:
{
  system.stateVersion = context.stateVersion;
}
