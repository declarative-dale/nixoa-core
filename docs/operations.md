# Operations

Run operator commands from the checkout or from the packages installed on the
appliance. Every system action uses `.#nixoa`.

## Inspect

```bash
nxcli status
nxcli status --json
nxcli host show
nxcli diff
nxcli history
nxcli generations list
```

## Apply configuration

Preview activation:

```bash
nxcli apply --dry-run
```

Build without activation:

```bash
nxcli apply --build
```

Switch immediately:

```bash
nxcli apply
```

Set the next boot generation without changing the running system:

```bash
nxcli boot
```

`--ask`, `--cores N`, and `--verbose` are forwarded to `nh`. Arguments after
`--` are forwarded to the underlying build.

## Roll back

```bash
nxcli rollback --ask
```

For an unbootable generation, choose a prior generation in the bootloader.
Boot entries are bounded to ten generations.

## Update

Preview all input changes:

```bash
nxcli update flake --preview
```

Update all inputs:

```bash
nxcli update flake
```

Preview or update only Xen Orchestra:

```bash
nxcli update xoa --preview
nxcli update xoa
```

Review `flake.lock`, build, and commit intentionally.

## Logs

Follow XO and Valkey:

```bash
nxcli xo logs
```

Other useful units:

```bash
journalctl -u xen-guest-agent.service
journalctl -u xo-autocert.service
journalctl -u xo-sudo-init.service
journalctl -u nixoa-rebuild.service
```

## Repository changes

```bash
nxcli diff
nxcli commit "Describe the appliance change"
nxcli history
```

The CLI tracks the configuration, scripts, packages, tests, and documentation.

## Maintenance

Automatic Nix garbage collection runs weekly and deletes unreachable paths
older than 30 days. The console also exposes an interactive `nh clean all`
action. Be aware that manual garbage collection can remove generations needed
for rollback.

Development mode:

```bash
nxcli host development-mode status
nxcli host development-mode on
nxcli host development-mode off
```
