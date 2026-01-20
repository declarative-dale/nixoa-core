# Repository Guidelines

## Project Structure & Module Organization
This repository is the NiXOA module library (nixoa-vm). Core system modules live in `modules/core/` and Xen Orchestra-specific modules live in `modules/xo/`. Nix packages are defined under `pkgs/` (for example, `pkgs/xen-orchestra-ce/`). Shared helpers sit in `lib/`, and operational scripts are in `scripts/`.

## Build, Test, and Development Commands
- `nix flake check .`: Validate flake inputs and basic evaluation.
- `sudo nixos-rebuild switch --flake .#HOSTNAME -L`: Rebuild a system using this flake (typically from a user-config repo that imports it).
- `scripts/xoa-update.sh`: Update the XO source input in `flake.lock`.
- `scripts/xoa-logs.sh`: Tail service logs for XO and related units.

## Coding Style & Naming Conventions
- Nix files use 2-space indentation and snake/short filenames (for example, `modules/xo/xoa.nix`).
- Keep options in the `nixoa.*` namespace and group related settings under `core` or `xo` modules.
- Shell scripts are POSIX-ish `bash` with `.sh` extensions; keep them executable and minimal.

## Testing Guidelines
- Primary validation is `nix flake check .` plus a dry-run or rebuild on a target system.
- There is no separate unit test suite in this repo; add checks in Nix or scripts when needed.

## Commit & Pull Request Guidelines
- Commit messages are short, imperative, and sentence case (examples in `git log`).
- PRs should describe the module or package change, include config examples if behavior changes, and link relevant issues or docs updates.

## Security & Configuration Notes
- This repo is an implementation library; user-specific values belong in the user-config repository.
- Avoid editing generated files or machine-specific values here; keep modules reusable and declarative.
