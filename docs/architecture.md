# Architecture

NiXOA is intentionally a single-appliance Den flake. `flake.nix` evaluates the
`modules/` import tree, and Den materializes one host entity:

```text
den.hosts.x86_64-linux.nixoa
└── nixosConfigurations.nixoa
```

The `nixoa` host aspect composes four focused aspects:

```text
nixoa
├── platform   NixOS base, networking, Nix policy, DBus safeguards
├── xcp-ng     Xen guest agent and constrained NoCloud provisioning
├── xo         Xen Orchestra service, TLS, and storage
└── operator   nixoa account, SSH, Home Manager, nxcli, and menu
```

There is no exported namespace, downstream template, physical-host variant,
synthetic VM configuration, or compatibility alias.

The native XCP-ng template builder is an operator-side tool, not another NixOS
configuration. `packages.x86_64-linux.installer-iso` evaluates a small live
installer, while `nix run .#deploy-template` realizes Packer and its XenServer
plugin only in the caller's Nix store. The sole installed system remains
`nixosConfigurations.nixoa`.

## Module layout

```text
modules/
├── dendritic.nix
├── den-defaults.nix
├── host.nix
├── aspects/
│   ├── platform.nix
│   ├── xcp-ng.nix
│   ├── xo.nix
│   └── operator.nix
├── _nixos/
│   ├── platform.nix
│   ├── xcp-ng.nix
│   ├── operator.nix
│   └── xo/
│       ├── default.nix
│       ├── service.nix
│       ├── tls.nix
│       └── storage.nix
└── _homeManager/
```

The underscore directories contain class modules and are not loaded as
flake-level modules by `import-tree`.

## Host ownership

`host/default.nix` imports three policy layers:

- `settings.nix`: operator-maintained settings
- `hardware-configuration.nix`: generated during bootstrap and the sole source
  of filesystems, swap, disks, and hardware discovery
- `menu.nix`: generated console overrides

Menu-managed operator values are defaults in `settings.nix`, so explicit values
in `menu.nix` take precedence without allowing the TUI to rewrite durable
policy.

## Clone provisioning

The XCP-ng aspect enables cloud-init for Xen Orchestra NoCloud config drives.
Its scope is deliberately narrow: select `NoCloud` with a `None` fallback,
target the existing `nixoa` operator, install datasource SSH keys, and create
per-instance SSH identity. Declarative NixOS configuration remains
authoritative for the hostname, network, accounts, sudo, filesystems, packages,
and services. Cloud-init disk growth, filesystem resize, network rendering,
package installation, and arbitrary user scripts are not enabled.

SSH starts after `cloud-config.service`, so a clone cannot expose the operator
login before NoCloud keys have been processed.

## XO runtime

`modules/_nixos/xo/service.nix` owns the `xo` account, Valkey instance,
generated TOML, filesystem layout, and hardened `xo-server` unit.

`tls.nix` creates a long-lived self-signed certificate when configured files
are absent or expired.

`storage.nix` provides NFS/CIFS/VHD support. XO remains unprivileged; mount and
libvhdi operations cross privilege boundaries only through a validated root
helper and a narrow sudo rule. CIFS credentials travel over standard input and
are written to a short-lived root-only credential file, never to process
arguments.

## Operational invariants

- target and host entity: `nixoa`
- architecture: `x86_64-linux`
- hypervisor: XCP-ng/Xen
- operator: `nixoa`
- initial state version: `26.05`
- direct XO package:
  `inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce`
