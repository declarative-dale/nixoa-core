# Getting Started (Core)

Core is a module library. The recommended entrypoint is the `system/` repo, but
you can also consume core directly in your own flake.

## Use Core From a Host Flake

```nix
{
  inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core?ref=beta";

  outputs = { nixoaCore, nixpkgs, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [ nixoaCore.nixosModules.appliance ];
    };
  };
}
```

## Update Core

From your host repo:

```bash
nix flake update
```

Core is fetched via flake inputs; no local clone is required.
