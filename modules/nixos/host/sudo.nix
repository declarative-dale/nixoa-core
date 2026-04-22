# SPDX-License-Identifier: Apache-2.0
# Administrator sudo policy
{
  context,
  ...
}:
{
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;

    extraRules = [
      {
        users = [ context.username ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
