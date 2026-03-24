# Core Architecture

NiXOA core is an immutable **module library** and package layer. It uses a
den-style dendritic module tree so hosts can consume curated module stacks,
overlays, and packages without the old bespoke registry layer.

## Repository Shape

```
core/
├── flake.nix
├── modules/
│   ├── dendritic.nix          # loads den framework modules
│   ├── nixos-modules.nix      # exported stack modules
│   ├── overlays.nix           # flake overlays
│   ├── packages.nix           # flake package outputs
│   └── _nixos/
│       └── features/
│       ├── foundation/        # shared module args + helpers
│       ├── platform/          # base platform features
│       │   ├── boot/           # loader + initrd
│       │   ├── identity/       # hostname/locale/shells/state
│       │   ├── networking/     # network defaults, firewall, NFS client
│       │   ├── packages/       # base packages + Nix settings
│       │   ├── services/       # journald + monitoring defaults
│       │   └── users/          # accounts, sudo, SSH
│       ├── virtualization/    # Xen hardware + guest agent
│       └── xo/                # XO service, storage, TLS, CLI
├── lib/                       # shared helpers
└── scripts/                   # maintenance utilities
```

## Curated Exports

[`modules/nixos-modules.nix`](../../modules/nixos-modules.nix) defines the
curated stack outputs:

- **platform**: base platform only
- **xo**: XO services only
- **appliance**: platform + virtualization + xo

The raw NixOS modules live under `modules/_nixos/` so `import-tree` only loads
the dendritic top-level modules.

## How Settings Flow In

System configuration lives in the host repo (the `system/` flake). It produces
`vars` from `config/default.nix` (which aggregates `config/`). Those values are
injected via `specialArgs` and `_module.args` into core modules.

```
config/* → configuration.nix → vars → specialArgs → core modules → NixOS config
```

## Relationship to System

`system/` imports core as a flake input and selects the exported stack modules
from `nixoaCore.nixosModules`.
