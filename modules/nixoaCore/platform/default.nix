{
  den,
  nixoaCore,
  ...
}:
{
  nixoaCore.platform = {
    includes = [ (den._.import-tree ./. ) ];
  };
}
