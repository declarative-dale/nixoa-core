{ inputs, ... }:
{
  imports = [ (inputs.import-tree ../hosts) ];
}
