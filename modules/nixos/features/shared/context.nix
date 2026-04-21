# SPDX-License-Identifier: Apache-2.0
# Shared module arguments for context-aware aspect modules
{
  lib,
  context ? { },
  ...
}:
let
  utils = import ../../../../lib/utils.nix { inherit lib; };
in
{
  _module.args = {
    inherit context;
    nixoaUtils = utils;
  };
}
