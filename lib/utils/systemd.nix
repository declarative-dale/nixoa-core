# SPDX-License-Identifier: Apache-2.0
# Systemd helpers
{ lib, ... }:
{
  # Service template helper
  mkSystemdService =
    {
      description,
      after ? [ ],
      requires ? [ ],
      wantedBy ? [ "multi-user.target" ],
      ...
    }@args:
    lib.filterAttrs (
      n: v: n != "description" && n != "after" && n != "requires" && n != "wantedBy"
    ) args
    // {
      inherit
        description
        after
        requires
        wantedBy
        ;
    };
}
