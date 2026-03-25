# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra runtime limits
{
  vars,
  ...
}:
{
  security.pam.loginLimits = [
    {
      domain = vars.xoUser;
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = vars.xoUser;
      type = "hard";
      item = "nofile";
      value = "1048576";
    }
  ];
}
