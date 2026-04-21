{
  # deadnix: skip
  __findFile ? __findFile,
  nixoa,
  ...
}:
{
  nixoa.appliance.includes = [
    <nixoa/platform>
    <nixoa/virtualization>
    <nixoa/xen-orchestra>
  ];
}
