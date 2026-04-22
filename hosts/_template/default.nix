{
  __findFile ? __findFile,
  den,
  inputs,
  lib,
  ...
}:
(import ../../lib/mk-host.nix) {
  inherit __findFile den inputs lib;
  hostRoot = ./.;
}
