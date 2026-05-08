# nxcli Reference

`nxcli` is the canonical operator interface for NiXOA. It owns host creation, apply/boot/rollback, repository commits, flake updates, XOA input updates, status, logs, and generation inspection.

Before the first successful apply, run it from the repo checkout:

```bash
nix run .#nxcli -- <command>
```

After the host has applied successfully, `nxcli` is installed on the system:

```bash
nxcli <command>
```

## Command Summary

```text
nxcli help
nxcli version
nxcli status [--json]
nxcli apply [--target <hostname|hostname-vm|vm>] [--build|--dry-run|--first-install] [--ask] [--cores N] [--verbose] [-- extra nh args...]
nxcli boot [--target <hostname|hostname-vm|vm>] [--ask] [--cores N] [--verbose] [-- extra nh args...]
nxcli rollback [--target <hostname|hostname-vm|vm>] [--ask]
nxcli commit [commit message]
nxcli diff [--json]
nxcli history
nxcli host add [hostname] [options]
nxcli host list [--json]
nxcli host show [hostname|hostname-vm|vm] [--json]
nxcli host select-vm <hostname|hostname-vm|vm>
nxcli host edit [hostname|hostname-vm|vm]
nxcli update flake [--preview] [--target <hostname|hostname-vm|vm>] [--ask]
nxcli update xoa [--preview] [--target <hostname|hostname-vm|vm>] [--ask]
nxcli xo logs
nxcli generations list
```

## Targets

Most system-mutating commands accept `--target`.

- `<hostname>` targets `nixosConfigurations.<hostname>`
- `<hostname>-vm` targets the per-host VM output
- `vm` resolves through `host/_automation/default.nix`

Use `vm` for automation that should follow the selected VM host. Use a concrete hostname when an operation must stay pinned to one host.

## Help And Version

```bash
nxcli help
nxcli version
```

`help` prints the top-level command summary. `version` prints the `nxcli`
version and, when available, the active NixOS version.

## Status

```bash
nxcli status
nxcli status --json
```

Text status reports the repo root, stable VM host, active target, XO service
state, Redis/Valkey compatibility service state, and tracked git state.

`--json` returns the state used by `nixoa-menu`, including host context,
repository state, memory/storage summaries, network URL, XOA version, rebuild state, and last apply information when present.

## Apply, Boot, And Rollback

```bash
nxcli apply --target <target>
nxcli apply --target <target> --build
nxcli apply --target <target> --dry-run
nxcli boot --target <target>
nxcli rollback --target <target>
```

Options:

- `--target TARGET`: select a host output; accepts host, host VM, or `vm`
- `--hostname TARGET`: legacy alias for `--target`
- `--build`: build without switching
- `--dry-run`: preview the apply flow without mutating the system
- `--first-install`: use first-install cache flags for the initial switch
- `--ask`: ask before mutating actions when supported
- `--cores N`: pass the requested core count to `nh`
- `--verbose`: increase `nh` verbosity
- `--`: pass remaining arguments through to the underlying build command

`apply` and `boot` use `nh` for normal rebuilds. `rollback` and first-install switches use `nixos-rebuild` where appropriate. If tracked NiXOA files are dirty, text-mode `nxcli apply` warns and continues; `nixoa-menu` prompts to commit dirty tracked files before applying.

## Repository Changes

```bash
nxcli diff
nxcli diff --json
nxcli history
nxcli commit "Describe the change"
nxcli commit
```

`diff` shows tracked NiXOA changes under the configured tracked paths.
`diff --json` returns a machine-readable list of changed tracked files.
`history` shows recent commits that touched tracked NiXOA paths.

`commit` stages tracked NiXOA paths and creates a commit. If no message is
provided in an interactive terminal, it prompts. If the prompt is left blank, it generates a structured commit body from the staged files.

Use this to save flake changes:

```bash
nxcli commit "Update flake inputs"
```

## Host Management

```bash
nxcli host add [hostname] [options]
nxcli host list [--json]
nxcli host show [hostname|hostname-vm|vm] [--json]
nxcli host select-vm <hostname|hostname-vm|vm>
nxcli host edit [hostname|hostname-vm|vm]
```

`host add` creates `host/<hostname>/` from `host/_template/`, writes host-owned
settings, optionally copies `/etc/nixos/hardware-configuration.nix`, updates the stable VM alias, stages new host files, validates the flake, and can run the first switch. It requires a clean tracked NiXOA worktree before it starts.

`host add` options:

- `--profile physical|vm`: deployment profile; defaults from virtualization detection
- `--copy-hardware`: copy `/etc/nixos/hardware-configuration.nix`; default
- `--skip-hardware-copy`: create the host without copying hardware config
- `--set-vm-alias`: point the stable `vm` alias at this host; default
- `--no-set-vm-alias`: leave the stable VM alias unchanged
- `--username NAME`: primary operator username; default `nixoa`
- `--git-name NAME`: git `user.name`; default `NiXOA Admin`
- `--git-email EMAIL`: git `user.email`; default `nixoa@nixoa`
- `--timezone ZONE`: time zone; default `Europe/Paris`
- `--state-version VER`: NixOS state version; default `25.11`
- `--ssh-key KEY`: add an SSH public key; repeatable
- `--skip-check`: skip `nix flake check --no-write-lock-file`
- `--first-switch`: run the first switch after host creation

`host edit` opens the selected host's `_ctx/settings.nix` and `_ctx/menu.nix`
with the configured editor.

`host list --json` returns host names, deployment profiles, and stable VM
selection state. `host show --json` returns the selected host, settings files, profile, username, timezone, repo directory, concrete outputs, and stable VM selection state.

## Updating Flake Inputs

```bash
nxcli update flake --preview
nxcli update flake
nxcli update xoa --preview
nxcli update xoa
```

Options:

- `--preview`: compute and print a lock-file diff without changing `flake.lock`
- `--target TARGET`: select the target shown in suggested follow-up commands
- `--hostname TARGET`: legacy alias for `--target`
- `--ask`: ask for confirmation before updating

`update flake` updates all flake inputs and prints suggested follow-up commands.
If `flake.lock` changes, save it with `nxcli commit`.

`update xoa` updates only the `xen-orchestra-ce` input. It requires the tracked NiXOA files to be clean before mutating, and commits the `flake.lock` update when the lock entry changes.

## XO Logs

```bash
nxcli xo logs
```

Tails `xo-build`, `xo-server`, and the detected Redis/Valkey compatibility
service with `journalctl`.

## Generations

```bash
nxcli generations list
```

Lists system generations from `/nix/var/nix/profiles/system`. It runs through
root access when needed.

## Flake Apps

The repo also exposes convenience apps that route to `nxcli`:

```bash
nix run .#nxcli -- <command>
nix run .#apply -- --target vm
nix run .#commit -- "Describe the change"
nix run .#diff -- --json
nix run .#history
nix run .#menu
```

The `menu` app launches `nixoa-menu`, not `nxcli`.
