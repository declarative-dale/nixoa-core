{
  den,
  nixoaCore,
  ...
}:
{
  nixoaCore."xen-orchestra" = {
    includes = [ (den._.import-tree ./. ) ];
  };
}
