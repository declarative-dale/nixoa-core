# Getting Started (Core)

The recommended way to use core is through the separate `system/` host flake.
If you want to consume core directly, add it as an input and import one or more
of the curated stacks.

Current release series: `v3.0.0`

```nix
{
  inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";

  outputs = { nixoaCore, nixpkgs, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [
        nixoaCore.nixosModules.platform
        nixoaCore.nixosModules.virtualization
        nixoaCore.nixosModules.xenOrchestra
      ];
    };
  };
}
```
