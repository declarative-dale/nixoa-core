# SPDX-License-Identifier: Apache-2.0
# Shared module arguments for feature-centric composition
{
  lib,
  vars ? { },
  ...
}:
let
  utils = import ../../../lib/utils.nix { inherit lib; };
in
{
  _module.args = {
    inherit vars;
    nixoaUtils = utils;
  };
}
