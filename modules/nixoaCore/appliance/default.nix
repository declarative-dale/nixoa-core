{
  __findFile ? __findFile,
  nixoaCore,
  ...
}:
{
  nixoaCore.appliance.includes = [
    <nixoaCore/platform>
    <nixoaCore/xcp-ng-guest>
    <nixoaCore/xo>
  ];
}
