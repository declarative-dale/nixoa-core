# Troubleshooting

## Flake output is missing

Confirm the checkout is complete and evaluate the fixed output:

```bash
nix flake show
nix eval .#nixosConfigurations.nixoa.config.networking.hostName
```

New flake files must be staged or addressed through a `path:` flake reference.
There should be no `vm`, `nixo-ce-example`, or `nixoaCore` output.

## Packer cannot discover the XenServer plugin

Use the flake app rather than a host Packer installation:

```bash
nix run --accept-flake-config .#deploy-template -- --help
```

The app wraps pinned nixpkgs Packer with the pinned plugin and an immutable
checksum file. `packer init` must not need to write into the Nix store.

## Packer cannot download the installer artifact

Authenticate GitHub CLI and confirm that a successful installer workflow is
available on `main`:

```bash
gh auth login
gh run list --repo declarative-dale/nixoa-core \
  --workflow cache-nixoa-menu.yml --branch main --status success
```

The default artifact is resolved at deployment time and is not pinned by
`flake.lock`. If it is unavailable or the newest workflow has not completed,
build the current checkout exactly with:

```bash
INSTALLER_SOURCE=build \
  nix run --accept-flake-config .#deploy-template -- ...
```

If a build VM remains after a failure, Packer's `keep_vm = "on_success"` policy
means it was not finalized as the successful NiXOA template. Inspect its
console and Packer output before removing it.

## SSH access fails after bootstrap

The final SSH policy allows only `nixoa`. Root and the installer `nixos`
account are denied.

Check the key list in `host/settings.nix` or `host/menu.nix`, then verify from
the VM console:

```bash
sudo sshd -T | grep -E 'allowusers|passwordauthentication|permitrootlogin'
getent passwd nixoa
```

For a clone provisioned by Xen Orchestra, also inspect NoCloud:

```bash
cloud-id
cloud-init status --wait --long
journalctl -u cloud-init-local.service -u cloud-init.service \
  -u cloud-config.service -b
```

`cloud-id` should report `nocloud` when a config drive is attached. Without a
config drive, the appliance uses the declared keys from `host/settings.nix` or
`host/menu.nix`; password SSH remains disabled.

## XO does not start

```bash
systemctl status redis-xo.service xo-server.service
journalctl -u redis-xo.service -u xo-server.service -b
```

Confirm `/etc/xo-server/config.nixoa.toml` exists and that the XO package has
`bin/xo-server` plus `libexec/xen-orchestra`.

## Xen clocksource or guest-agent warnings

Valkey may warn that the Xen clocksource is slower than TSC. NiXOA retains the
Xen-selected clocksource because forcing TSC can make timekeeping unsafe across
VM save, restore, or migration. Xen's default TSC mode is designed to preserve
correctness while using native TSC when the host and migration path make it
safe. See the [Xen TSC mode documentation](https://xenbits.xen.org/docs/unstable/man/xen-tscmode.7.html).

The Rust Xen guest agent may also report that a newer kernel supplied more
IPv6 netlink data than its parser knows. If the service remains active, has no
restarts, and reports addresses to XCP-ng, this is informational. Prefer the
reviewed Nixpkgs package and update it with the locked nixpkgs input instead of
substituting an uncached upstream development snapshot merely to hide the
message.

## TLS fails

```bash
systemctl status xo-autocert.service
journalctl -u xo-autocert.service -b
sudo openssl x509 -in /etc/ssl/xo/certificate.pem -noout -subject -dates
```

Remove or replace expired/broken runtime certificate files, then restart
`xo-autocert.service` followed by `xo-server.service`.

## Remote storage fails

Follow XO logs while reproducing the operation:

```bash
nxcli xo logs
```

Mount targets must be under `nixoa.xo.storage.mountsDir`. VHD paths must be
under the XO mounts, data, or temporary directories. The helper rejects
disabled filesystems, arbitrary commands, and CIFS secrets in command-line
options.

For CIFS probes, verify the service path includes the NiXOA `mount.cifs` shim.
For VHD, verify the selected libvhdi package provides `vhdimount` and
`vhdiinfo`.

## Hardware or boot fails

NiXOA does not override filesystems. Compare
`host/hardware-configuration.nix` with the VM's generated configuration and
check that bootloader settings match its firmware.

Boot a previous generation from the systemd-boot menu if necessary.

## A TUI change disappeared

The menu rewrites `host/menu.nix` as a complete generated override. Durable
manual changes belong in `host/settings.nix`.

## Apply reports a dirty checkout

Dirty appliance paths are allowed for development but are reported. Inspect
and commit them:

```bash
nxcli diff
nxcli commit "Describe the change"
```
