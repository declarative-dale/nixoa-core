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

## Feature Stacks

Defined in `parts/nix/registry/features.nix`:

- **system**: platform only
- **xo**: XO services only
- **appliance**: platform + virtualization + xo

## Full Tree (Core)

```
core/
├── AGENTS.md                         # repo-specific guidance
├── CHANGELOG.md                      # release history
├── LICENSE                           # Apache-2.0
├── README.md                         # this file
├── flake.nix                         # generated entrypoint (flake-parts)
├── flake.lock                        # pinned inputs
├── nixoa-cli.sh                      # helper CLI
├── docs/                             # library docs
│   ├── architecture.md
│   ├── common-tasks.md
│   ├── configuration.md
│   ├── getting-started.md
│   ├── installation.md
│   ├── operations.md
│   └── troubleshooting.md
├── legal/                            # legal and contribution docs
│   ├── CONTRIBUTING.md
│   ├── NOTICE
│   └── headers/
├── lib/                              # shared helpers
│   └── utils.nix
├── modules/
│   └── features/
│       ├── foundation/
│       │   └── args.nix
│       ├── platform/
│       │   ├── boot/
│       │   │   ├── default.nix
│       │   │   ├── initrd.nix
│       │   │   └── loader.nix
│       │   ├── identity/
│       │   │   ├── default.nix
│       │   │   ├── hostname.nix
│       │   │   ├── locale.nix
│       │   │   ├── shells.nix
│       │   │   └── state.nix
│       │   ├── networking/
│       │   │   ├── base.nix
│       │   │   ├── default.nix
│       │   │   ├── firewall.nix
│       │   │   └── nfs.nix
│       │   ├── packages/
│       │   │   ├── default.nix
│       │   │   └── system.nix
│       │   ├── services/
│       │   │   ├── default.nix
│       │   │   ├── journald.nix
│       │   │   └── prometheus.nix
│       │   └── users/
│       │       ├── accounts.nix
│       │       ├── default.nix
│       │       ├── ssh.nix
│       │       └── sudo.nix
│       ├── virtualization/
│       │   ├── xen-guest.nix
│       │   └── xen-hardware.nix
│       └── xo/
│           ├── cli.nix
│           ├── config.nix
│           ├── extras.nix
│           ├── options.nix
│           ├── tls.nix
│           ├── service/
│           │   ├── assertions.nix
│           │   ├── default.nix
│           │   ├── packages.nix
│           │   ├── redis.nix
│           │   ├── systemd.nix
│           │   └── tmpfiles.nix
│           └── storage/
│               ├── assertions.nix
│               ├── default.nix
│               ├── filesystems.nix
│               ├── packages.nix
│               ├── sudo.nix
│               ├── tmpfiles.nix
│               └── wrapper.nix
├── parts/                            # flake-parts wiring
│   ├── flake/
│   │   ├── exports.nix
│   │   └── per-system.nix
│   └── nix/
│       ├── flake-parts/
│       │   ├── dendritic-tools.nix
│       │   └── lib.nix
│       ├── inputs/
│       │   └── core.nix
│       └── registry/
│           └── features.nix
└── scripts/                          # maintenance utilities
    ├── migrate-redis-to-valkey.sh
    ├── xoa-install.sh
    ├── xoa-logs.sh
    └── xoa-update.sh
```

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
