# Configuration

All appliance-specific configuration lives under `host/`.

## `host/settings.nix`

This is the durable, hand-maintained module. It sets native NixOS options plus
the typed NiXOA option trees.

Core NixOS settings include:

```nix
networking.hostName = "nixoa";
time.timeZone = "America/Chicago";
system.stateVersion = "26.05";
boot.loader.systemd-boot.enable = true;
networking.firewall.allowedTCPPorts = [80 443];
```

Do not change `system.stateVersion` after installation.

## Operator options

`nixoa.operator` controls the fixed `nixoa` account:

| Option | Purpose |
|---|---|
| `repoDir` | appliance checkout path |
| `gitName`, `gitEmail` | commit identity |
| `sshKeys` | authorized SSH public keys |
| `enableExtras` | zsh and expanded shell tooling |
| `developmentMode` | Rust, Node.js, and service-development tools |
| `menuAutoStart` | launch the TUI automatically on SSH login |
| `sudoNoPassword` | operator sudo policy |
| `systemPackages`, `userPackages` | package attribute paths |

`username` is typed and read-only; it is always `nixoa`.

## XO options

`nixoa.xo` controls Xen Orchestra:

| Option | Default |
|---|---|
| `enable` | configured `true` |
| `package` | direct x86_64 `xo-nixpkg` output |
| `user`, `group` | `xo`, `xo` |
| `home` | `/var/lib/xo` |
| `dataDir`, `cacheDir`, `tempDir` | under `home` |
| `httpHost` | `0.0.0.0` |
| `config.toml` | generated structured default |
| `redis.maxmemory` | unlimited |
| `redis.maxmemoryPolicy` | `noeviction` |

TLS options are under `nixoa.xo.tls`: `enable`, `autoCert`, `dir`, `cert`, and
`key`.

Storage options are under `nixoa.xo.storage`: `enableNFS`, `enableCIFS`,
`enableVHD`, `mountsDir`, and `libvhdiPackage`.

When `config.toml` is empty, NiXOA generates an XO configuration for Valkey,
HTTP/HTTPS listeners, web mounts, runtime directories, and privileged remote
storage through the validated helper. A non-empty value replaces that generated
TOML completely.

## Hardware configuration

`host/hardware-configuration.nix` is the only disk and filesystem source.
Regenerate it on the appliance when hardware changes:

```bash
sudo nixos-generate-config --show-hardware-config \
  > /tmp/hardware-configuration.nix
sudo install -m 0644 /tmp/hardware-configuration.nix \
  /home/nixoa/nixoa/host/hardware-configuration.nix
```

Review before applying.

## NoCloud clone data

The appliance accepts a Xen Orchestra NoCloud config drive. Its public SSH keys
are installed for the declared `nixoa` account. The hostname remains `nixoa`,
systemd-networkd remains authoritative for DHCP, and cloud-init is not allowed
to partition, resize, or otherwise redefine the generated hardware layout.

For a reusable template, clear cloud-init state, machine identity, and SSH host
keys before sealing it. The Packer workflow performs and verifies that step.

## TUI overrides

`host/menu.nix` is generated. It may override SSH keys, extras, development
mode, extra packages, and selected service enables. Do not put
hand-maintained policy there; the next menu action rewrites the whole file.
