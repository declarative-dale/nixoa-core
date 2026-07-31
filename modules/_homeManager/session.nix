# SPDX-License-Identifier: Apache-2.0
# Home session variables
{osConfig, ...}: let
  operator = osConfig.nixoa.operator;
in {
  home.sessionVariables = {
    NIXOA_SYSTEM_ROOT = operator.repoDir;
    XO_MOUNTS = osConfig.nixoa.xo.storage.mountsDir;
  };
}
