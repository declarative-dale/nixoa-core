# Installation (Core)

NiXOA core is not installed directly. It is a flake library consumed by a host
flake such as `system/`.

Current release series: `v2.0.0`

```nix
inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";
```

Then import either the full appliance:

```nix
modules = [ nixoaCore.nixosModules.appliance ];
```

or the more granular stacks:

```nix
modules = [
  nixoaCore.nixosModules.platform
  nixoaCore.nixosModules.virtualization
  nixoaCore.nixosModules.xenOrchestra
];
```
