{
  den,
  nixoaCore,
  ...
}:
{
  nixoaCore.virtualization = {
    includes = [ (den._.import-tree ./. ) ];
  };
}
