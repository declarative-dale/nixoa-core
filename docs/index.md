# Documentation

New to NiXOA? Read [Getting started](getting-started.md). It explains how to
reach the appliance, check its health, and make a safe first change.

## Find what you need

| I want to… | Read… |
|---|---|
| install NiXOA | [Installation](installation.md) |
| learn the everyday workflow | [Getting started](getting-started.md) |
| change SSH keys, packages, TLS, or storage | [Common tasks](common-tasks.md) |
| understand the configuration files and options | [Configuration](configuration.md) |
| update, apply, or roll back the appliance | [Operations](operations.md) |
| look up a command | [`nxcli` reference](nxcli.md) |
| fix a problem | [Troubleshooting](troubleshooting.md) |
| understand how NiXOA is built | [Architecture](architecture.md) |
| inspect flake outputs, artifacts, or automation | [Project reference](project-reference.md) |

## The three ideas that matter

1. NiXOA is one appliance, not a multi-host framework. Commands always target
   `.#nixoa`.
2. Durable settings belong in `host/settings.nix`. The console owns
   `host/menu.nix`.
3. Preview changes with `nxcli apply --dry-run`; use `nxcli rollback --ask` if
   an activated change causes trouble.

For development and packaging details, see the
[Packer reference](../packer/README.md), [architecture](architecture.md), and
[project reference](project-reference.md), or read the
[contribution guide](../legal/CONTRIBUTING.md).
