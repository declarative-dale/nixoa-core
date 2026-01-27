# SPDX-License-Identifier: Apache-2.0
# Platform service bundle
{ ... }:
{
  imports = [
    ./journald.nix
    ./prometheus.nix
  ];
}
