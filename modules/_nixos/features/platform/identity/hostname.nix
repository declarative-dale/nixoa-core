# SPDX-License-Identifier: Apache-2.0
# Hostname configuration
{
  vars,
  ...
}:
{
  networking.hostName = vars.hostname;
}
