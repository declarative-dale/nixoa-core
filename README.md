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

Deploy a native XCP-ng template directly from a checkout. Nix provides the
Packer toolchain on demand; it is not installed into a profile or the appliance:

```bash
nix run .#deploy-template -- \
  --host XCP_POOL_MASTER \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "VM network" \
  --export-network "VM network" \
  --template-name NiXOA \
  --operator-key ~/.ssh/id_ed25519.pub
```

For an existing, normally installed NixOS VM, bootstrap remains supported. The
VM must already have `/etc/nixos/hardware-configuration.nix`.

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
- `packages.x86_64-linux.installer-iso`
- operator apps: `nxcli`, `apply`, `bootstrap`, `commit`, `diff`, `history`,
  `menu`, and `deploy-template`

GitHub Actions builds all public packages and the cache-rich installer ISO. It
retains the complete ISO as the `nixoa-installer` workflow artifact while
publishing only the smaller reusable NiXOA package closures to Cachix. The
flake app downloads the newest successful `main` artifact, verifies its
published SHA-256 checksum, and passes it directly to Packer without requiring
a local ISO build or checkout copy.

Use `nix run --accept-flake-config .#deploy-template -- ...` so the initial
deployer package can also be substituted from the declared caches. Authenticate
the GitHub CLI with `gh auth login` before downloading workflow artifacts.

A second workflow runs every Wednesday at 09:17 UTC and refreshes every input
in `flake.lock`. When anything changes it creates or refreshes a pull request;
merging that pull request is the only step that applies the new lock to `main`.

## Documentation

- [Getting started](docs/getting-started.md)
- [Installation](docs/installation.md)
- [Architecture](docs/architecture.md)
- [Configuration](docs/configuration.md)
- [Operations](docs/operations.md)
- [`nxcli` reference](docs/nxcli.md)
- [Troubleshooting](docs/troubleshooting.md)

NiXOA is licensed under Apache License 2.0.
