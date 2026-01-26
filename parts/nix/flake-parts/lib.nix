{ lib, ... }:
{
  # Shared helpers for future core extensions.
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };
}
