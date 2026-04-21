# Installation (Core)

NiXOA core is not installed directly. It is a flake library consumed by a host
flake such as `system/`, or by another Den flake that wants to import the
NiXOA namespace.

Current release series: `v3.1.0`

```nix
inputs.den.url = "github:vic/den";
inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";
```

Then import the namespace:

```nix
imports = [
  inputs.den.flakeModules.dendritic
  (inputs.den.namespace "nixoa" [ inputs.nixoaCore ])
];
```

Enable angle brackets if you want Den's terse namespace lookups:

```nix
_module.args.__findFile = den.lib.__findFile;
```

Then include either the full appliance or the individual NiXOA aspects from
your host aspect:

```nix
den.aspects.${context.hostname}.includes = [ <nixoa/appliance> ];
```

```nix
den.aspects.${context.hostname}.includes = [
  <nixoa/platform>
  <nixoa/virtualization>
  <nixoa/xen-orchestra>
];
```
