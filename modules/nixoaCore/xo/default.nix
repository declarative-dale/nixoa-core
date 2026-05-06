{
  den,
  nixoaCore,
  ...
}:
{
  nixoaCore.xo = {
    includes = [ (den._.import-tree ./. ) ];
  };
}
