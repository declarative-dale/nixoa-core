# SPDX-License-Identifier: Apache-2.0
# Sudo and security limits
{
  vars,
  ...
}:
{
  config = {
    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;

      extraRules = [
        {
          users = [ vars.username ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

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
  };
}
