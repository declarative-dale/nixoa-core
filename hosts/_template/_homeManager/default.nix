# SPDX-License-Identifier: Apache-2.0
# Host-local Home Manager composition for the primary NiXOA operator
{ inputs, ... }:
{
  imports = [ (inputs.import-tree ../../../modules/_homeManager) ];
}
