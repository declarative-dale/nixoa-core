# SPDX-License-Identifier: Apache-2.0
# Host time settings
{
  context,
  ...
}:
{
  time.timeZone = context.timezone;
}
