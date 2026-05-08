{
  den,
  nixoaCore,
  ...
}: {
  nixoaCore.xcp-ng-guest = {
    includes = [(den._.import-tree ./.)];
  };
}
