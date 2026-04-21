{
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.den.flakeModules.dendritic ];

  options.flake-file.inputs = lib.mkOption {
    default = { };
    defaultText = lib.literalExpression "{ }";
    type = lib.types.lazyAttrsOf lib.types.raw;
    internal = true;
    visible = false;
  };
}
