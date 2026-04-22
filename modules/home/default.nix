# SPDX-License-Identifier: Apache-2.0
# Home Manager profile root
{ ... }:
{
  imports = [
    ./base.nix
    ./packages.nix
    ./session.nix
    ./tools.nix
    ./shell
  ];
}
