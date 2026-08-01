# Installation

NiXOA supports two installation paths:

| Starting point | Use |
|---|---|
| A new appliance | [Create an XCP-ng template](#create-an-xcp-ng-template) |
| An existing NixOS VM on XCP-ng | [Bootstrap the VM](#use-an-existing-nixos-vm) |

Creating a template is the recommended path. It gives you a clean appliance
that can be cloned whenever you need it.

## Create an XCP-ng template

### Before you begin

You need:

- Nix with flakes enabled
- `gh`, authenticated with `gh auth login`
- access to the XCP-ng pool master
- a DHCP-enabled network
- an SSH public key for the `nixoa` operator

### Deploy

```bash
git clone https://codeberg.org/NiXOA/core.git
cd core

nix run --accept-flake-config .#deploy-template -- \
  --host XCP_POOL_MASTER \
  --iso-sr "ISO library" \
  --sr "Local storage" \
  --network "VM network" \
  --export-network "VM network" \
  --template-name NiXOA \
  --operator-key ~/.ssh/id_ed25519.pub
```

The deployer prompts for missing XCP-ng details and the password. It stores
non-secret answers in `packer/local.pkrvars.json`; it never stores the
password.

> The installer erases the one virtual disk created for the temporary build
> VM. Check the selected storage and VM details before confirming.

### Create your appliance

When the build completes:

1. Clone the `NiXOA` template in Xen Orchestra.
2. Attach a NoCloud config drive with an SSH key for `nixoa`.
3. Boot the clone and note its IP address.
4. Continue with [Getting started](getting-started.md).

Each clone creates fresh machine and SSH host identities.

## Use an existing NixOS VM

Use this path only for a normally installed `x86_64` NixOS guest on XCP-ng.
The VM must boot, have working networking, and contain
`/etc/nixos/hardware-configuration.nix`.

From the VM:

```bash
git clone https://codeberg.org/NiXOA/core.git /tmp/nixoa-bootstrap
cd /tmp/nixoa-bootstrap

sudo ./scripts/bootstrap.sh \
  --repo-dir /home/nixoa/nixoa \
  --ssh-key 'ssh-ed25519 AAAA... operator@example'
```

Replace the example with your complete public key. Repeat `--ssh-key` to add
more than one key.

Bootstrap keeps the VM's generated disk and filesystem configuration, checks
the flake, and activates `.#nixoa`. After activation, SSH access is available
only as `nixoa`, so verify the key before you continue.

Run `./scripts/bootstrap.sh --help` for optional settings such as the time
zone, Git identity, branch, or a validation-only install.

## Advanced deployment details

The default template deployment downloads and verifies the latest successful
installer artifact. To build the installer from the current checkout instead:

```bash
INSTALLER_SOURCE=build \
  nix run --accept-flake-config .#deploy-template -- ...
```

To deploy a specific installer image, set `INSTALLER_ISO=/path/to/image.iso`.
For the complete build, validation, cache, and sealing contract, see the
[Packer reference](../packer/README.md).

[Back to documentation](index.md)
