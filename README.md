# NiXOA

**Xen Orchestra, packaged as a focused NixOS VM appliance for XCP-ng.**

NiXOA builds a reproducible Xen Orchestra appliance, seals it as an XCP-ng
template, and gives each clone its own machine identity.

```text
XCP-ng pool  →  NiXOA virtual machine  →  Xen Orchestra web interface
```

## What you get

- Xen Orchestra Community Edition with reviewable NixOS configuration
- verified installer, SPDX and CycloneDX SBOMs, and build attestations
- atomic upgrades, boot generations, and rollbacks
- a guided console plus the `nxcli` operator command

## Launch NiXOA

Install Nix and Git, authenticate GitHub CLI with `gh auth login`, and have an
SSH public key plus XCP-ng pool access ready. Then run:

```bash
git clone https://github.com/declarative-dale/nixoa-core.git
cd nixoa-core

nix run --accept-flake-config .#deploy-template -- \
  --host XCP_POOL_MASTER \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "VM network" \
  --export-network "VM network" \
  --template-name NiXOA \
  --operator-key ~/.ssh/id_ed25519.pub
```

The deployer downloads the latest verified installer, prompts for XCP-ng
details, and builds a sealed `NiXOA` template. It saves reusable non-secret
answers while accepting the XCP-ng password at execution time.

Clone the template, attach a NoCloud config drive with the operator SSH key,
and boot the appliance. Continue with the
[first-login guide](docs/getting-started.md).

## Build from this checkout

Build the installer ISO directly from the flake:

```bash
nix build --accept-flake-config .#installer-iso
```

The ISO is available at `result/iso/nixoa-installer.iso`. Build and deploy the
same checkout in one operation with:

```bash
INSTALLER_SOURCE=build \
  nix run --accept-flake-config .#deploy-template -- \
  --host XCP_POOL_MASTER \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "VM network" \
  --export-network "VM network" \
  --template-name NiXOA \
  --operator-key ~/.ssh/id_ed25519.pub
```

The [installation guide](docs/installation.md) also covers bootstrapping an
existing NixOS guest and supplying an exact installer image.

## First login

Open Xen Orchestra at `https://<vm-address>/`, or connect to the appliance:

```bash
ssh nixoa@<vm-address>
nxcli status
nixoa-menu
```

Use `nxcli apply --dry-run` to preview a configuration generation and
`nxcli apply` to activate it.

## Documentation

| Goal | Guide |
|---|---|
| Install and connect | [Installation](docs/installation.md) and [getting started](docs/getting-started.md) |
| Operate and update | [Operations](docs/operations.md) and [`nxcli` reference](docs/nxcli.md) |
| Customize the appliance | [Common tasks](docs/common-tasks.md) and [configuration](docs/configuration.md) |
| Diagnose an issue | [Troubleshooting](docs/troubleshooting.md) |
| Build and contribute | [Development](docs/development.md), [architecture](docs/architecture.md), and [project reference](docs/project-reference.md) |

The complete task-oriented map is in the [documentation index](docs/index.md).

NiXOA is licensed under the [Apache License 2.0](LICENSE). Contributions are
welcome; see the [contribution guide](legal/CONTRIBUTING.md).
