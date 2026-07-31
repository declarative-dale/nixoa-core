# NiXOA

NiXOA is a focused NixOS appliance for running Xen Orchestra Community Edition
inside an x86_64 XCP-ng virtual machine. The flake defines exactly one system:

```text
nixosConfigurations.nixoa
```

The appliance combines:

- Xen Orchestra from `xo-nixpkg`
- Valkey-backed XO state
- automatic self-signed TLS
- NFS, CIFS, and VHD/VHDX storage support
- Xen guest integration
- constrained NoCloud/cloud-init support for cloned VM identity and SSH keys
- Determinate Nix and XO/libvhdi binary caches
- a locked-down `nixoa` SSH operator with Home Manager
- `nxcli` and the `nixoa-menu` console

## Install

Start from an installed NixOS VM on XCP-ng. The VM must already have a generated
`/etc/nixos/hardware-configuration.nix`.

```bash
git clone https://codeberg.org/NiXOA/core.git /tmp/nixoa-bootstrap
cd /tmp/nixoa-bootstrap
sudo ./scripts/bootstrap.sh \
  --repo-dir /home/nixoa/nixoa \
  --ssh-key 'ssh-ed25519 AAAA... operator@example'
```

Bootstrap writes the fixed appliance settings, copies the generated hardware
module, validates `.#nixoa`, and performs the first switch. Use
`--no-first-switch` to stop after validation.

## Operate

All commands target `.#nixoa`; there is no host selector or VM alias.

```bash
nxcli status
nxcli apply
nxcli boot
nxcli rollback
nxcli update xoa --preview
nxcli xo logs
nixoa-menu
```

The hand-maintained configuration and generated state live together under
`host/`:

```text
host/
├── default.nix
├── settings.nix
├── hardware-configuration.nix
└── menu.nix
```

Edit `host/settings.nix` for durable policy. `nixoa-menu` writes only
`host/menu.nix`, so console changes never rewrite the hand-maintained module.

## Flake outputs

- `nixosConfigurations.nixoa`
- `packages.x86_64-linux.xen-orchestra-ce`
- `packages.x86_64-linux.libvhdi`
- `packages.x86_64-linux.nxcli`
- `packages.x86_64-linux.nixoa-menu`
- operator apps: `nxcli`, `apply`, `bootstrap`, `commit`, `diff`, `history`,
  and `menu`

## Documentation

- [Getting started](docs/getting-started.md)
- [Installation](docs/installation.md)
- [Architecture](docs/architecture.md)
- [Configuration](docs/configuration.md)
- [Operations](docs/operations.md)
- [`nxcli` reference](docs/nxcli.md)
- [Troubleshooting](docs/troubleshooting.md)

NiXOA is licensed under Apache License 2.0.
