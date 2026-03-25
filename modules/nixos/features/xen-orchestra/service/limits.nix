# SPDX-License-Identifier: Apache-2.0
# Xen Orchestra runtime limits
{
  config,
  ...
}:
let
  cfg = config.nixoa.xo;
in
{
  security.pam.loginLimits = [
    {
      domain = cfg.user;
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = cfg.user;
      type = "hard";
      item = "nofile";
      value = "1048576";
    }
  ];
}
