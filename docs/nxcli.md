# `nxcli` Reference

`nxcli` is the canonical operator interface. It always targets `.#nixoa`.

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

## Fixed target

Host selection and alias resolution were removed. `--target`, `--hostname`,
`host add`, `host list`, and `host select-vm` return errors. The flake reference
is always:

```text
path:<checkout>#nixoa
```

## Apply, boot, and rollback

Normal apply and boot operations use `nh os` with the direct
`nixosConfigurations.nixoa` path. `--first-install` uses `nixos-rebuild`
directly and supplies flake/cache options needed before the declarative Nix
configuration is active.

Rollback calls `nixos-rebuild switch --rollback`.

Successful and failed operations write state under
`/var/lib/nixoa/apply-state.env`. The TUI reads that file to report whether a
rebuild is needed.

## Repository commands

`diff`, `commit`, and `history` are scoped to NiXOA-owned paths. `commit` stages
those paths and uses `nixoa.operator.gitName` and `gitEmail`.

## Host commands

`host show` reports the fixed target and the three host policy files.
`host edit` opens `host/settings.nix` and `host/menu.nix`.
`host development-mode` changes only the generated menu override.

## Updates

`update flake --preview` and `update xoa --preview` write an updated temporary
lock file and show the diff without changing the checkout.

Without `--preview`, the corresponding input is updated in `flake.lock`. The
CLI does not apply or commit the result automatically.

## JSON

`status --json` returns the same snapshot consumed by the TUI. `diff --json`
returns tracked path statuses and names for machine-readable integrations.
