{
  __findFile ? __findFile,
  den,
  inputs,
  lib,
  ...
}:
(import ../../lib/host.nix) {
  inherit __findFile den inputs lib;
  hostRoot = ./.;
}
