# SPDX-License-Identifier: Apache-2.0
# Boot feature bundle
{ ... }:
{
  imports = [
    ./loader.nix
    ./initrd.nix
  ];
}
