# Repository Guidelines

## Project Structure & Module Organization
This repository is the NiXOA core appliance library. Public flake outputs are defined under `modules/outputs/`, while plain NixOS implementation modules live under `modules/nixos/features/` with `shared`, `platform`, `virtualization`, and `xen-orchestra` slices. Shared helpers live in `lib/`, and operational XO maintenance scripts live in `scripts/`.

## Build, Test, and Development Commands
- `nix flake check --no-write-lock-file`: Validate flake evaluation.
- `nix build .#packages.x86_64-linux.xen-orchestra-ce --no-link`: Validate the packaged XO build.
- `scripts/xoa-update.sh`: Update the XO source input in `flake.lock`.
- `scripts/xoa-logs.sh`: Tail XO-related logs on a running host.

## Coding Style & Naming Conventions
- Keep public output modules explicit and small. If a file belongs to the flake surface, it should live under `modules/outputs/`.
- Keep machine-specific policy out of core. User-editable values belong in the system repository.
- Prefer explicit stack names like `virtualization` and `xenOrchestra` over registry-style indirection.

## Testing Guidelines
- Primary validation is `nix flake check --no-write-lock-file` plus targeted `nix build` dry-runs for exported packages.
- If you change a public stack, also validate the downstream `system` host flake.

## Commit & Pull Request Guidelines
- Commit messages should describe the exported surface, package graph, or module layout change being made.
- If a change affects the public stack names or library shape, update `README.md` and `docs/architecture.md` in the same commit.

## Security & Configuration Notes
- Core is intentionally host-agnostic and does not ship installation/bootstrap logic.
- Do not reintroduce `denful` exports unless the repository intentionally becomes a shared den aspect distribution.
