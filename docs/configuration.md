# Configuration

Most users only need one file:

```text
host/settings.nix
```

It contains durable appliance settings such as the time zone, SSH keys,
packages, TLS, and storage support. Run `nxcli host edit` to open the host
configuration files.

## Configuration files

| File | Purpose | Edit by hand? |
|---|---|---|
| `host/settings.nix` | Durable appliance policy | Yes |
| `host/hardware-configuration.nix` | Generated disks, filesystems, and detected hardware | Only when hardware changes |
| `host/menu.nix` | Overrides written by `nixoa-menu` | No |

The menu rewrites `host/menu.nix` as a complete file. Put lasting manual
changes in `host/settings.nix`.

## Safe editing workflow

```bash
nxcli host edit
nxcli diff
nxcli apply --dry-run
nxcli apply
```

NiXOA creates a new NixOS generation for every applied change. If needed, use
`nxcli rollback --ask`.

## Common settings

The main NiXOA options are grouped by purpose:

| Option group | Controls |
|---|---|
| `nixoa.operator.sshKeys` | SSH public keys for the `nixoa` account |
| `nixoa.operator.systemPackages` | Packages available system-wide |
| `nixoa.operator.userPackages` | Packages for the operator |
| `nixoa.operator.enableExtras` | Extra shell tools and zsh |
| `nixoa.operator.developmentMode` | Rust, Node.js, and development tools |
| `nixoa.operator.menuAutoStart` | Whether the console opens at SSH login |
| `nixoa.xo.tls` | HTTPS certificates |
| `nixoa.xo.storage` | NFS, CIFS, and VHD support |

The operator name, flake target, platform, and appliance role are fixed. They
do not need configuration.

See [Common tasks](common-tasks.md) for copyable examples.

## Native NixOS settings

`host/settings.nix` can also set normal NixOS options. The checked-in defaults
include the host name, time zone, bootloader, firewall ports, and state version.

Do not raise `system.stateVersion` just because NixOS was updated. It records
the compatibility version used when the appliance was first installed.

## Hardware changes

`host/hardware-configuration.nix` is the only source of filesystem, swap, and
disk declarations. If the VM hardware changes, generate a candidate on the
appliance and review it before replacing the existing file:

```bash
sudo nixos-generate-config --show-hardware-config \
  > /tmp/hardware-configuration.nix
```

NoCloud may grow the existing root partition and filesystem when a cloned disk
is larger. It does not create filesystems, install packages, or replace the
declarative network and hardware configuration.

[Back to documentation](index.md)
