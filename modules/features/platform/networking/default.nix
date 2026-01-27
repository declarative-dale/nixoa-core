# SPDX-License-Identifier: Apache-2.0
# Networking feature bundle
{ ... }:
{
  imports = [
    ./base.nix
    ./firewall.nix
    ./nfs.nix
  ];
}
