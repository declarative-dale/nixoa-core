# SPDX-License-Identifier: Apache-2.0
# Centralized utility library for NiXOA modules
{ lib }:
let
  parts = [
    (import ./utils/types.nix { inherit lib; })
    (import ./utils/get-option.nix { inherit lib; })
    (import ./utils/options.nix { inherit lib; })
    (import ./utils/validators.nix { inherit lib; })
    (import ./utils/systemd.nix { inherit lib; })
    (import ./utils/module-lib.nix { inherit lib; })
  ];
in
lib.foldl' (acc: part: acc // part) { } parts
