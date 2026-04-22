{ lib, ... }:
let
  hostParts = [
    (import ./settings.nix { inherit lib; })
    (import ./menu.nix { inherit lib; })
  ];
in
lib.foldl' lib.recursiveUpdate { } hostParts
