# NiXOA Core

NiXOA core is the **immutable module library** and package layer for NiXOA. It
ships reusable NixOS modules, Xen Orchestra CE packages, and a dendritic
flake-parts layout meant to be consumed by a host-specific flake.

## Getting Started

Start with the ecosystem guide:
- `../.profile/README.md`

It walks through cloning the system repo and applying your first configuration.

## What Core Provides

- `nixosModules.*` feature modules and stacks
- `overlays.nixoa` exposing `pkgs.nixoa.*`
- shared helpers under `lib/`

## Layout (Dendritic)

```
core/
├── flake.nix                 ← generated entrypoint
├── parts/                    ← flake-parts modules
│   ├── flake/                ← outputs (nixosModules, overlays)
│   └── nix/                  ← inputs + registry helpers
├── modules/
│   └── features/
│       ├── foundation/       ← shared module args
│       ├── platform/         ← base system features
│       ├── virtualization/   ← Xen VM and guest integration
│       └── xo/               ← Xen Orchestra services & tooling
├── pkgs/                     ← package definitions
├── lib/                      ← shared utilities
└── scripts/                  ← maintenance scripts
```

## Feature Stacks

Defined in `parts/nix/registry/features.nix`:

- **system**: platform only
- **xo**: XO services only
- **appliance**: platform + virtualization + xo

## Example (Direct Import)

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

## Notes

- Core is **version controlled** and **not** host-specific.
- User settings belong in the `system/` repo (`config/` files).

## License

Apache-2.0
