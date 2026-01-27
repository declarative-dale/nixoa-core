# NiXOA Core

NiXOA core is the **immutable module library** and package layer for NiXOA. It
ships reusable NixOS modules, Xen Orchestra CE packages, and a dendritic
flake-parts layout meant to be consumed by a host-specific flake (the `system/`
repo).

- **Who edits this?** Contributors and maintainers.
- **Who uses this?** Host configuration repos that import it as a flake input.

## Relationship to `system/`

`system/` is the user-editable, host-specific flake. It pulls in this repo and
imports the `appliance` stack (or individual features) from `nixosModules`.

Core provides:
- `nixosModules.*` feature modules and stacks
- `overlays.nixoa` overlay exposing `pkgs.nixoa.*`
- helper utilities under `lib/`

## Layout (Dendritic)

```
core/
├── flake.nix                 ← generated entrypoint (flake-parts + import-tree)
├── parts/                    ← dendritic flake-parts modules
│   ├── flake/                ← outputs (nixosModules, overlays)
│   └── nix/                  ← inputs + registry helpers
├── modules/
│   └── features/
│       ├── foundation/       ← shared module args
│       ├── platform/         ← base system features (identity/boot/network/etc.)
│       ├── virtualization/   ← Xen VM and guest integration
│       └── xo/               ← Xen Orchestra services & tooling
├── pkgs/                     ← package definitions (xen-orchestra-ce, libvhdi)
├── lib/                      ← shared utilities
├── scripts/                  ← maintenance scripts
└── docs/                     ← architecture and ops docs
```

## Feature Sets (Stacks)

Core exposes feature modules and stacks via `nixosModules`:

- **system**: platform features only
- **xo**: Xen Orchestra features only
- **appliance**: platform + virtualization + xo

Stacks are defined in `parts/nix/registry/features.nix`.

## Examples

Import the full appliance stack:

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

Or import a single feature:

```nix
{
  modules = [
    inputs.nixoaCore.nixosModules.xo-service
  ];
}
```

## Notes

- Core is **version controlled** and **not** host-specific.
- User-specific settings belong in the `system/` repo (`config/` files).
- The dendritic layout keeps features discoverable and composable.

## Commands

- `nix flake check .`
- `scripts/xoa-update.sh`

## License

Apache-2.0
