# SPDX-License-Identifier: Apache-2.0
# Generic service enables from menu-managed config
{
  lib,
  context,
  ...
}:
let
  mkServiceEnable =
    name: lib.setAttrByPath ([ "services" ] ++ lib.splitString "." name ++ [ "enable" ]) true;
in
{
  config = lib.mkMerge (map mkServiceEnable (context.enabledServices or [ ]));
}
