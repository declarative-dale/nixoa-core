# `nxcli` Reference

`nxcli` is the command-line interface for the NiXOA appliance. Every command
targets `.#nixoa`; there is no host selector.

## Commands

```text
nxcli help
nxcli version
nxcli status [--json]
nxcli apply [--build|--dry-run|--first-install] [--ask] [--cores N] [--verbose] [-- ...]
nxcli boot [--ask] [--cores N] [--verbose] [-- ...]
nxcli rollback [--ask]
nxcli commit [MESSAGE]
nxcli diff [--json|--staged]
nxcli history
nxcli host show [--json]
nxcli host edit
nxcli host development-mode [status|on|off|toggle]
nxcli update flake [--preview] [--ask]
nxcli update xoa [--preview] [--ask]
nxcli xo logs
nxcli generations list
```

## Build and activation

| Command | Result |
|---|---|
| `nxcli apply --dry-run` | Shows what activation would change |
| `nxcli apply --build` | Builds without activating |
| `nxcli apply` | Builds and activates now |
| `nxcli boot` | Builds and selects the generation for next boot |
| `nxcli rollback` | Switches to the previous generation |

`--ask`, `--cores N`, and `--verbose` are passed to `nh`. Arguments after `--`
are passed to the underlying build.

`--first-install` is reserved for bootstrap. It uses `nixos-rebuild` directly
before the appliance's declarative Nix configuration is active.

## Repository commands

- `diff` shows changes to NiXOA-owned files.
- `commit` stages those files and creates a commit using the configured Git
  identity.
- `history` shows the repository history.

## Host commands

- `host show` reports the fixed target and its policy files.
- `host edit` opens the durable settings, native XO configuration, and
  generated menu overrides.
- `host development-mode` changes the development-tools override.

## Updates

`update flake` updates all locked inputs. `update xoa` updates only Xen
Orchestra. Add `--preview` to view the lock-file change without modifying the
checkout.

After an update, review the lock-file diff, apply the generation, and record it
with `nxcli commit`.

## Machine-readable output

- `status --json` returns the status snapshot used by the console.
- `diff --json` returns changed paths and Git status codes.

[Back to documentation](index.md)
