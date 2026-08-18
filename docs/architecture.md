# Architecture

> This is an advanced reference for contributors. For normal installation and
> operation, start with [Getting started](getting-started.md).

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
installer, while `nix run --accept-flake-config .#deploy-template` realizes
Packer and its XenServer plugin only in the caller's Nix store. The sole
installed system remains `nixosConfigurations.nixoa`.

The flake directly declares the Determinate, NiXOA, Xen Orchestra, and libvhdi
binary caches. The multi-gigabyte installer is instead a GitHub Actions
artifact: the `deploy-template` app selects the newest successful `main` run,
downloads and verifies the ISO at deployment time, and passes its temporary
path to Packer. The artifact is not a flake input or lock-file entry. An exact
checkout-local ISO remains available through `INSTALLER_SOURCE=build`.

Repository delivery is Nix-defined and devenv-orchestrated. A shared devenv
module supplies both the native shell/task graph and the compatible flake
development shell. Its tasks call `packages.x86_64-linux.nixoa-ci`, which owns
the tested installer and release decisions. Workflows retain GitHub security
boundaries—permissions, OIDC, artifacts, attestations, Cachix, and FlakeHub—but
do not implement repository policy inline. A Nix policy declares which source
paths affect the immutable installer fingerprint, allowing metadata-only
commits to reuse a previously verified artifact while unknown paths fail
safely toward rebuilding.

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
per-instance SSH identity. Declarative NixOS configuration remains authoritative
for accounts, sudo, network configuration, filesystem declarations, packages,
and services. Cloud-init may install NoCloud SSH keys and grow only the existing
root partition and filesystem. Network rendering, package installation, and
arbitrary user scripts are not enabled; systemd-networkd may apply a
DHCP-provided transient hostname through the narrowly authorized hostnamed
action.

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

[Back to documentation](index.md)
