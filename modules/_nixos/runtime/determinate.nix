# SPDX-License-Identifier: Apache-2.0
# Determinate Nix module
{
  inputs,
  ...
}:
{
  imports = [ inputs.determinate.nixosModules.default ];
}
