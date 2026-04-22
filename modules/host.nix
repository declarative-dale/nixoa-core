{ inputs, ... }:
{
  imports = [ (inputs.import-tree ../host) ];
}
