# Repository Guidelines

## Project Structure & Module Organization
This repository is the NiXOA core aspect namespace. Den bootstrap and namespace wiring live in `modules/dendritic.nix`, `modules/den-defaults.nix`, and `modules/namespace.nix`. Reusable exported aspects live under `modules/nixoaCore/`, while shared hidden implementation modules live under `modules/_nixos/` and `modules/_homeManager/`. Shared helpers live in `lib/`, and operational XO maintenance scripts live in `scripts/`.

## Build, Test, and Development Commands
- `nix flake check --no-write-lock-file`: Validate flake evaluation.
- `nix build .#packages.x86_64-linux.xen-orchestra-ce --no-link`: Validate the packaged XO build.
- `scripts/xoa-update.sh`: Update the XO source input in `flake.lock`.
- `scripts/xoa-logs.sh`: Tail XO-related logs on a running host.

## Coding Style & Naming Conventions
- Keep reusable NiXOA behavior in namespaced aspects under `nixoa.*`; use plain implementation modules only behind those aspect definitions.
- Keep machine-specific policy out of core. User-editable context values belong in the system repository.
- Prefer aspect names and `includes`/`provides` terminology over stack or module-library wording.

## Testing Guidelines
- Primary validation is `nix flake check --no-write-lock-file` plus targeted `nix build` dry-runs for exported packages.
- If you change a public aspect tree, also validate the downstream `system` host flake.

## Commit & Pull Request Guidelines
- Commit messages should describe the exported aspect surface, package graph, or module layout change being made.
- If a change affects the public namespace or aspect names, update `README.md` and `docs/architecture.md` in the same commit.

## Security & Configuration Notes
- Core is intentionally host-agnostic and does not ship installation/bootstrap logic.
- Keep `flake.denful.nixoa` as the primary reusable surface; do not reintroduce `nixosModules` as the main API.
