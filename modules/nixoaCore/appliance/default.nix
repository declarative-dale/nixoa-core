{
  __findFile ? __findFile,
  nixoaCore,
  ...
}:
{
  nixoaCore.appliance.includes = [
    <nixoaCore/platform>
    <nixoaCore/virtualization>
    <nixoaCore/xen-orchestra>
  ];
}
