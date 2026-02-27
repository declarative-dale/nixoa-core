# Installation (Core)

NiXOA core is a module library and package layer. You typically **do not**
install it directly. Use the `system/` repo (host configuration) which pulls
core as a flake input.

If you want to consume core in a custom flake, add it as an input:

```nix
inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core?ref=beta";
```

Then import the stack you want:

```nix
modules = [ nixoaCore.nixosModules.appliance ];
```
