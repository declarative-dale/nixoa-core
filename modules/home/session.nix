# SPDX-License-Identifier: Apache-2.0
# Home session variables
{
  context,
  ...
}:
{
  home.sessionVariables = {
    NIXOA_SYSTEM_ROOT = context.repoDir or "/home/${context.username}/nixoa";
    XO_MOUNTS = context.mountsDir;
  };
}
