# Getting Started (Core)

The recommended way to use core is through the separate `system/` host flake.
If you want to consume core directly, add it as an input and import the NiXOA
namespace into your own Den flake.

Current release series: `v3.1.0`

```nix
{
  inputs.den.url = "github:vic/den";
  inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";

  outputs = inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [
        ({ den, ... }: {
          imports = [
            inputs.den.flakeModules.dendritic
            (inputs.den.namespace "nixoa" [ inputs.nixoaCore ])
          ];

          _module.args.__findFile = den.lib.__findFile;

          den.hosts.x86_64-linux.my-host = { };
          den.aspects.my-host.includes = [ <nixoa/appliance> ];
        })
      ];
    }).config.flake;
}
```

For more granular composition, include any of the named aspects directly:

```nix
{
  den.aspects.my-host.includes = [
    <nixoa/platform>
    <nixoa/virtualization>
    <nixoa/xen-orchestra>
  ];
}
```
