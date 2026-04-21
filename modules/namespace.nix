{ inputs, den, ... }:
{
  imports = [ (inputs.den.namespace "nixoa" true) ];

  _module.args.__findFile = den.lib.__findFile;
}
