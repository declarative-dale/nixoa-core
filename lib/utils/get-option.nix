# SPDX-License-Identifier: Apache-2.0
# Safe nested attribute access
{ lib, ... }:
{
  # Usage: getOption vars ["xo" "port"] 80
  # Returns: vars.xo.port or 80 if not found
  getOption =
    settings: path: default:
    let
      getValue =
        cfg: pathList:
        if pathList == [ ] then
          cfg
        else if builtins.isAttrs cfg && builtins.hasAttr (builtins.head pathList) cfg then
          getValue cfg.${builtins.head pathList} (builtins.tail pathList)
        else
          null;
      result = getValue settings path;
    in
    if result == null then default else result;
}
