# SPDX-License-Identifier: Apache-2.0
# System identity bundle
{ ... }:
{
  imports = [
    ./hostname.nix
    ./locale.nix
    ./shells.nix
    ./state.nix
  ];
}
