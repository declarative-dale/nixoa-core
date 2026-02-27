# Core Architecture

NiXOA core is an immutable **module library** and package layer. It uses
flake-parts and a dendritic feature registry so hosts can compose features
cleanly while keeping modules small.

## Repository Shape

```
core/
├── flake.nix
├── parts/
│   ├── flake/                 # outputs (nixosModules, overlays, per-system)
│   ├── inputs/                # flake input wiring
│   ├── per-system/            # per-system package outputs
│   └── registry/              # feature registry + composition helpers
├── modules/
│   └── features/
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

## Feature Registry

`parts/registry/features.nix` defines:

- **features**: small modules mapped to names
- **stacks**: named sets of features (e.g., `platform`, `xo`, `appliance`)

Feature definitions are grouped by domain in `parts/registry/features/` and
merged by `parts/registry/features.nix`.

`parts/registry/composition.nix` then builds `nixosModules.*` from the registry.

## How Settings Flow In

System configuration lives in the host repo (the `system/` flake). It produces
`vars` from `configuration.nix` (which aggregates `config/`). Those values are
injected via `specialArgs` and `_module.args` into core modules.

```
config/* → configuration.nix → vars → specialArgs → core modules → NixOS config
```

## Relationship to System

`system/` imports core as a flake input and selects the `appliance` stack (or
individual features) from `nixoaCore.nixosModules`.
