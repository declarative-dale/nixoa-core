# SPDX-License-Identifier: Apache-2.0
# Administrator sudo policy
{
  lib,
  context,
  ...
}:
let
  sudoNoPassword = context.sudoNoPassword or true;
in
{
  security.sudo = {
    enable = true;
    wheelNeedsPassword = !sudoNoPassword;

    extraRules = lib.optionals sudoNoPassword [
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
