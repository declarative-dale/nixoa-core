# SPDX-License-Identifier: Apache-2.0
# XO service feature set
{ ... }:
{
  imports = [
    ./assertions.nix
    ./redis.nix
    ./packages.nix
    ./systemd.nix
    ./tmpfiles.nix
  ];
}
