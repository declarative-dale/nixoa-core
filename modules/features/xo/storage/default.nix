# SPDX-License-Identifier: Apache-2.0
# XO storage feature set
{ ... }:
{
  imports = [
    ./wrapper.nix
    ./packages.nix
    ./filesystems.nix
    ./sudo.nix
    ./tmpfiles.nix
    ./assertions.nix
  ];
}
