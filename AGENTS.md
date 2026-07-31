# Repository Guidelines

## Scope

This repository is one appliance flake, not a multi-host framework. Its only
NixOS output is `nixosConfigurations.nixoa`, an x86_64 XCP-ng guest running Xen
Orchestra. Do not add host templates, compatibility aliases, or target
selection.

## Structure

- `modules/aspects/`: Den composition for platform, XCP-ng, XO, and operator
- `modules/_nixos/`: focused native NixOS modules
- `modules/_homeManager/`: the `nixoa` operator home
- `host/settings.nix`: hand-maintained appliance policy
- `host/hardware-configuration.nix`: bootstrap-generated hardware module
- `host/menu.nix`: TUI-generated overrides only
- `scripts/nxcli.sh`: operator CLI source
- `scripts/tui/`: console backend
- `pkgs/nixoa-menu/`: Ratatui frontend

## Development

Use `.#nixoa` in commands and documentation.

```bash
nix flake check --no-write-lock-file
nix build .#nixosConfigurations.nixoa.config.system.build.toplevel --no-link
nix build .#xen-orchestra-ce .#nxcli .#nixoa-menu --no-link
tests/run.sh
```

Run `bash -n` and ShellCheck for shell changes, and `cargo fmt --check`,
`cargo check`, and `cargo test` for menu changes.

## Configuration rules

- Declare operator policy under typed `nixoa.operator` options.
- Declare XO policy under typed `nixoa.xo` options.
- Keep filesystems and disks solely in `host/hardware-configuration.nix`.
- Preserve XO privilege separation and validated storage helpers.
- Preserve the DBus activation safeguards, bounded boot generations, Nix GC,
  Determinate Nix, and XO/libvhdi caches.
- SSH access is only for the declared `nixoa` operator.
- The TUI may write only `host/menu.nix`.

## Commits

Commit coherent implementation, tests, and documentation checkpoints. Keep
historical changelog entries intact and describe public-interface changes in
the current changelog section.
