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

## Quick Links

- [Getting Started](./docs/getting-started.md)
- [Installation](./docs/installation.md)
- [Configuration](./docs/configuration.md)
- [Architecture](./docs/architecture.md)
- [Operations](./docs/operations.md)
- [Troubleshooting](./docs/troubleshooting.md)

## Highlights

- Declarative Xen Orchestra service configuration
- HTTPS/TLS support with auto-generated certificates
- NFS/CIFS storage helpers and VHD support
- Xen guest agent and hardware defaults for VMs
- Flake-parts + dendritic feature registry for composition

## Feature Stacks

Defined in `parts/registry/features.nix`:

- **platform**: base platform only
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
│   ├── utils.nix
│   └── utils/
├── modules/
│   └── features/
│       ├── foundation/
│       │   └── args.nix
│       ├── platform/
│       │   ├── boot/
│       │   │   ├── initrd.nix
│       │   │   └── loader.nix
│       │   ├── identity/
│       │   │   ├── hostname.nix
│       │   │   ├── locale.nix
│       │   │   ├── shells.nix
│       │   │   └── state-version.nix
│       │   ├── networking/
│       │   │   ├── defaults.nix
│       │   │   ├── firewall.nix
│       │   │   └── nfs.nix
│       │   ├── packages/
│       │   │   └── base-packages.nix
│       │   ├── services/
│       │   │   ├── journald.nix
│       │   │   └── prometheus.nix
│       │   └── users/
│       │       ├── accounts.nix
│       │       ├── ssh.nix
│       │       └── sudo.nix
│       ├── virtualization/
│       │   ├── xen-guest.nix
│       │   └── xen-hardware.nix
│       └── xo/
│           ├── cli.nix
│           ├── config-link.nix
│           ├── dev-tools.nix
│           ├── options-base.nix
│           ├── options-paths.nix
│           ├── options-tls.nix
│           ├── tls-service.nix
│           ├── tls-tmpfiles.nix
│           ├── service/
│           │   ├── assertions.nix
│           │   ├── packages.nix
│           │   ├── redis.nix
│           │   ├── start-script.nix
│           │   ├── tmpfiles.nix
│           │   └── unit.nix
│           └── storage/
│               ├── assertions.nix
│               ├── filesystems.nix
│               ├── libvhdi-options.nix
│               ├── packages.nix
│               ├── sudo-config.nix
│               ├── sudo-init.nix
│               ├── sudo-rules.nix
│               ├── tmpfiles.nix
│               └── wrapper-script.nix
├── parts/                            # flake-parts wiring
│   ├── flake/
│   │   ├── nixos-modules.nix
│   │   ├── outputs.nix
│   │   ├── overlays.nix
│   │   ├── per-system.nix
│   │   └── wiring.nix
│   ├── inputs/
│   │   └── base.nix
│   ├── per-system/
│   │   └── packages.nix
│   └── registry/
│       ├── composition.nix
│       ├── features.nix
│       └── features/
│           ├── platform.nix
│           ├── virtualization.nix
│           └── xo.nix
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

## Important Notice

This project is designed for homelab/testing environments. For production use,\nconsider the official Xen Orchestra Appliance from Vates.

## Resources

- Xen Orchestra docs: https://xen-orchestra.com/docs/
- NixOS learn: https://nixos.org/learn.html
- Core issues: https://codeberg.org/NiXOA/core/issues

## License

Apache-2.0
