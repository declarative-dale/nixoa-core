# SPDX-License-Identifier: Apache-2.0
# Common option helpers
{ lib, ... }:
let
  types = lib.types;
in
{
  # Helper to create a module option with common patterns
  mkDefaultOption =
    type: default: description:
    lib.mkOption {
      inherit type default description;
    };

  # Helper for enable options
  mkEnableOpt = description: lib.mkEnableOption description;

  # Helper to create a string option with default
  mkStrOption =
    default: description:
    lib.mkOption {
      type = types.str;
      inherit default description;
    };

  # Helper to create a port option
  mkPortOption =
    default: description:
    lib.mkOption {
      type = types.port;
      inherit default description;
    };

  # Helper to create a path option
  mkPathOption =
    default: description:
    lib.mkOption {
      type = types.path;
      inherit default description;
    };

  # Helper to create a boolean option with default
  mkBoolOption =
    default: description:
    lib.mkOption {
      type = types.bool;
      inherit default description;
    };

  # Helper to create a listOf strings option
  mkListOfStrOption =
    default: description:
    lib.mkOption {
      type = types.listOf types.str;
      inherit default description;
    };
}
