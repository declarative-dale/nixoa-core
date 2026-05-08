# Daily Operations

Common `nxcli` flows for operating NiXOA systems from the unified repo.

For complete syntax, options, and behavior notes, see the
[nxcli reference](nxcli.md).

## Status

```bash
cd ~/nixoa
nxcli status
```

`nxcli status` reports the repo root, selected stable VM host, active target, XO service state, Redis/Valkey backend state, and whether tracked repo files are clean.

## Service Management

```bash
sudo systemctl status xo-server.service
sudo systemctl restart xo-server.service
sudo systemctl status redis-xo.service
```

## Logs

```bash
nxcli xo logs
```

`nxcli xo logs` tails `xo-build`, `xo-server`, and the active Redis/Valkey
compatibility service. It replaces the old direct log helper script.

## Operator Console

```bash
nixoa-menu
```

The console uses a simple main menu/submenu flow: Up and Down move, Enter
selects, and Esc returns to the previous menu. Esc at the main menu asks whether to return to the shell. SSH autostart is disabled by default; enable
`nixoaMenuAutoStart = true;` in the host context only when SSH logins should
enter the console automatically.

## Edit Host Configuration

```bash
cd ~/nixoa
nxcli host edit nixo-ce
```

Edit the active host under `host/<hostname>/`, usually `_ctx/settings.nix`
and `_ctx/menu.nix`.

## Apply Configuration

```bash
cd ~/nixoa
nxcli apply --target <hostname>
```

Stable VM alias:

```bash
cd ~/nixoa
nxcli apply --target vm
```

Preview without mutating:

```bash
cd ~/nixoa
nxcli apply --target vm --dry-run
```

Build without switching:

```bash
cd ~/nixoa
nxcli apply --target <hostname> --build
```

## Boot On Next Reboot

```bash
cd ~/nixoa
nxcli boot --target vm
```

Use this when you want to stage a change for the next reboot instead of
switching immediately.

## Update Inputs

```bash
cd ~/nixoa
nxcli update flake --preview
nxcli update flake
nxcli commit "Update flake inputs"
nxcli update xoa
```

`nxcli commit` is the canonical command for saving tracked flake, host, package,
and script changes. `nxcli update xoa` updates only the `xen-orchestra-ce`
input and commits the lock-file change when it changes.

## Repository Changes

```bash
cd ~/nixoa
nxcli diff
nxcli diff --json
nxcli history
nxcli commit "Describe the change"
```

`nixoa-menu` also uses `nxcli commit` before apply when tracked files are dirty.

If the console commit prompt is left blank, it generates a message from the
current date and changed files.

## Rollback

```bash
cd ~/nixoa
nxcli rollback --target <hostname>
```
