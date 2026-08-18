# Operations

NiXOA commands operate directly on the single `.#nixoa` appliance.

## Everyday commands

| Goal | Command |
|---|---|
| Check health | `nxcli status` |
| Review local changes | `nxcli diff` |
| Preview activation | `nxcli apply --dry-run` |
| Build without activating | `nxcli apply --build` |
| Build and activate | `nxcli apply` |
| Use a new generation after reboot | `nxcli boot` |
| Roll back | `nxcli rollback --ask` |
| Follow XO logs | `nxcli xo logs` |
| Open the console | `nixoa-menu` |

For every available command and flag, see the [`nxcli` reference](nxcli.md).

## Apply a change

For a normal configuration change:

```bash
nxcli diff
nxcli apply --dry-run
nxcli apply
```

Use `nxcli boot` to make the new generation active after the next reboot.

## Roll back

```bash
nxcli rollback --ask
```

The boot menu provides older generations for recovery. NiXOA keeps up to ten
boot entries.

## Update

Preview updates before changing the lock file:

```bash
nxcli update flake --preview
nxcli update xoa --preview
```

Apply either update with the same command minus `--preview`:

```bash
nxcli update flake
nxcli update xoa
```

An update changes `flake.lock`. Review the diff, apply the new generation, and
record the lock-file update with `nxcli commit`.

## Inspect logs

Follow Xen Orchestra and Valkey together:

```bash
nxcli xo logs
```

Inspect an individual system service with `journalctl`, for example:

```bash
journalctl -u xo-server.service -b
journalctl -u xen-guest-agent.service -b
```

## Save repository changes

```bash
nxcli diff
nxcli commit "Describe the appliance change"
nxcli history
```

## Storage cleanup

Automatic Nix garbage collection runs weekly and removes unreachable paths
older than 30 days. The console also provides manual cleanup.

Manual cleanup can remove generations that would otherwise be available for a
rollback. Check the generation list first:

```bash
nxcli generations list
```

[Back to documentation](index.md)
