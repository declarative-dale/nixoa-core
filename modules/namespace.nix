{ inputs, den, ... }:
{
  imports = [ (inputs.den.namespace "nixoaCore" true) ];

  _module.args.__findFile = den.lib.__findFile;
}
