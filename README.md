# NiXOA Core

NiXOA Core is a NixOS appliance flake for running Xen Orchestra Community
Edition. It gives you a reproducible host layout, a packaged XO build, a single operator CLI, and an SSH-friendly console for day-to-day administration.

This repo can be used in two ways:

- as the concrete host flake for a NiXOA appliance
- as a reusable Den namespace through `flake.denful.nixoaCore`

## What You Get

- Xen Orchestra CE packaged from the pinned `xen-orchestra-ce` input
- `nxcli`, the supported command line for host and repository operations
- `nixoa-menu`, an xsconsole-style SSH operator console
- a host template under `host/_template/`
- concrete host outputs such as `nixosConfigurations.<hostname>` and `<hostname>-vm`
- `nixosConfigurations.vm`, a stable VM alias selected by `host/_automation/default.nix`
- reusable Den aspects: `<nixoaCore/platform>`, `<nixoaCore/xcp-ng-guest>`, `<nixoaCore/xo>`, and `<nixoaCore/appliance>`

## Quick Start

On a fresh NixOS install, the streamed bootstrap path prepares a checkout,
creates a host from the template, and can run the first switch:

```bash
bash <(curl -fsSL https://codeberg.org/NiXOA/core/raw/branch/main/scripts/bootstrap.sh) --enable-flakes --first-switch
```

If you prefer to clone the repo first:

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
nix run .#nxcli -- host add nixo-ce --first-switch
```

After the first successful apply, use the installed tools directly:

```bash
nxcli status
nixoa-menu
```

SSH logins open a normal shell by default. Run `nixoa-menu` manually, or set
`nixoaMenuAutoStart = true;` in the host context if SSH sessions should enter the console automatically.

## Common Commands

Before `nxcli` is installed on the host, prefix commands with
`nix run .#nxcli --` from the repo checkout.

```bash
nxcli status
nxcli apply --target vm
nxcli boot --target vm
nxcli diff
nxcli commit "Describe the change"
nxcli update flake --preview
nxcli update xoa
nxcli xo logs
```

See the full command reference in [docs/nxcli.md](docs/nxcli.md).

## Documentation

- [Installation](docs/installation.md): fresh install prep, bootstrap paths, and first apply
- [Getting Started](docs/getting-started.md): first host creation and initial operating flow
- [Daily Operations](docs/operations.md): status, logs, updates, commits, rollback, and `nixoa-menu`
- [nxcli Reference](docs/nxcli.md): complete CLI syntax, options, examples, and behavior notes
- [Configuration Reference](docs/configuration.md): host context values and editable files
- [Common Tasks](docs/common-tasks.md): short examples for frequent host edits
- [Troubleshooting](docs/troubleshooting.md): common operational failure modes
- [Architecture](docs/architecture.md): Den namespace, host assembly, and exported outputs
- [Changelog](CHANGELOG.md): release history and breaking changes

## Repository Layout

```text
core/
├── host/       # host template, concrete hosts, and the stable VM alias
├── modules/    # reusable aspects plus shared NixOS/Home Manager implementation
├── lib/        # shared Nix helpers
├── docs/       # operator and maintainer documentation
├── scripts/    # nxcli source, bootstrap wrapper, shared helpers, and TUI backend
└── flake.nix
```

## Notes For Maintainers

- `nxcli` is the canonical operator interface. Direct script execution is for bootstrap and internal plumbing.
- `nixoa-menu` uses `nxcli` for apply, rollback, and repository commits.
- Host-owned values belong under `host/<hostname>/`, not reusable core aspects.
- `flake.denful.nixoaCore` is the primary reusable public surface.
