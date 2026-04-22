# Daily Operations

Common `nxcli` flows for operating NiXOA systems from the unified repo.

## Status

```bash
cd ~/nixoa
nxcli status
```

`nxcli status` reports the repo root, selected stable VM host, active target,
XO service state, Redis/Valkey backend state, and whether tracked repo files
are clean.

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
nxcli update flake
nxcli update xoa
```

## Rollback

```bash
cd ~/nixoa
nxcli rollback --target <hostname>
```
