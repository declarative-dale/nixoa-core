<!-- SPDX-License-Identifier: Apache-2.0 -->
# Changelog

## v0.4 — Stability & Production Updates (Vates Camp 2025 Edition)

Date: 2025-12-03

This release focuses on stability improvements, NixOS 25.11 upgrade, v6 web UI support, terminal enhancements, and important production readiness clarifications.

### ✨ Added

**v6 Web UI Support**
- `/v6` mount now builds by default to match latest XOA updates for Xen Orchestra 5.113
- New web interface available alongside traditional v5 UI
- Proper build directory handling with explicit path navigation

**Enhanced Terminal Experience**
- Oh My Posh configured with Darcula theme (custom themes may be explored in future releases)
- `cat` command - Shows syntax highlighting without line numbers (easy to copy text)
- `catn` command - Shows syntax highlighting with line numbers (for reference)
- Removed `vivid` command that was causing errors (eza provides excellent colors natively)

**Licensing Updates**
- LICENSE file updates with proper Apache 2.0 attribution and copyright notices
- Added SPDX license identifiers to all project files for compliance
- Clarified open source licensing terms

**Documentation & Metadata**
- Updated flake.nix with correct repository metadata
- Production readiness warnings and alternative solutions for professional use

### 🔄 Changed

**Project Rebranding**
- Project renamed from "NixOA" to "NixOA-CE" (Community Edition)
- Repository URL updated: `declarative-xoa-ce` → `nixoa-ce`
- Updated all documentation and configuration references to reflect new naming
- Repository location in configs changed from `/etc/nixos/declarative-xoa-ce` to `/etc/nixos/nixoa-ce`
- Default `repoDir` in configuration now points to `/etc/nixos/nixoa-ce`
- **For existing users:** See [MIGRATION.md](./MIGRATION.md) for instructions on renaming your local repository directory

**System Updates**
- Upgraded to NixOS 25.11 (latest stable)
- All Nix files converted to Unix line endings for consistency
- Improved shell configuration priority handling using `lib.mkDefault`

**Build System Improvements**
- Build script now explicitly returns to `${cfg.xo.appDir}` instead of relative `cd ..`
- Replaced `lib.optionalString` with native Nix if-then-else in let blocks
- Fixed autocert service dependencies in both xo-build and xo-server services

**Module Cleanup**
- Removed duplicate module that was redundantly passing vars through `_module.args`
- Removed hardware configuration file checking logic (always required now)
- Simplified conditional logic for autocert service integration

### 🐛 Fixed

**Service Dependencies**
- Fixed xo-build.service to use `config.xoa.autocert.enable` correctly
- Fixed xo-server.service autocert dependency conditions
- Proper service ordering with `lib.optional` checks

**Terminal Configuration**
- Resolved shell priority conflicts between system.nix and extras.nix
- Fixed Oh My Posh theme rendering issues

### 📚 Important Notes

**Production Readiness**
- This project is **not production-ready** and is intended for testing and development
- For professional/production use, consider:
  - Official Xen Orchestra Appliance (XOA) from Vates
  - Xen Orchestra from Sources (manual installation)
  - Commercial support options from Vates

**Flake Purity**
- Sample `nixoa.toml` provided for flake purity compliance
- Hardware configuration is now always required (no conditional checks)

### 🗺️ Roadmap

**Upcoming Improvements**
- **Full Flake Purity:** Add local nixpkgs derivations for libvhdi and Xen Orchestra built from official repos using dream2nix, eliminating fetchFromGitHub dependencies and achieving complete flake reproducibility
- **Separate User Configuration Flake:** Develop a companion repository for user-specific flake inputs, removing the need to edit `nixoa.toml` within the nixoa-ce repository and improving the separation between upstream project code and user configuration

---

## v0.3 — TOML Migration & Custom Packages/Services

Date: 2025-11-26
This update migrates the configuration system from JSON to TOML for improved human readability, adds support for custom packages and services, and fixes a xo-server automatic startup issue.

### ✨ Added

**Custom Packages**
- `packages.system.extra` - Add custom system-wide packages
- `packages.user.extra` - Add custom packages for admin user only
- Packages specified by nixpkgs attribute name (e.g., "docker-compose", "neovim")

**Custom Services**
- `services.enable` - Simple list to enable common NixOS services with defaults
- `[services.servicename]` - Configure services with custom options (e.g., docker, tailscale, postgresql)
- Supports any NixOS service with full configuration flexibility
- Services configuration inserted directly into modules/system.nix

**Configuration Naming**
- Renamed: `config.toml` → `nixoa.toml`
- Renamed: `config.sample.toml` → `sample-nixoa.toml`
- More descriptive and project-specific naming

### 🔄 Changed

**XenOrchestra Startup**
- Fixed an issue where xo-server would not start if VM was rebooted

**Configuration Format Migration (JSON → TOML)**
- Migrated from `config.json` to `nixoa.toml` for better readability
- Updated `vars.nix` to use `builtins.fromTOML` instead of `builtins.fromJSON`
- Converted `config.sample.json` to `sample-nixoa.toml` with improved comments
- Updated `.gitignore` to reference `nixoa.toml`
- Updated all documentation to reflect TOML format

### 📚 Migration Notes

For existing users with `config.json`:
1. The structure is nearly identical - main difference is syntax
2. See CONFIGURATION-COMPARISON.md for conversion guide
3. Key changes: Remove quotes from keys, use `#` for comments, objects become `[sections]`
4. Rename your config file to `nixoa.toml`

---

# v0.2 — Beta Release

Date: 2025-11-25
This release introduces the new JSON-based configuration system, major refinements to the mounting subsystem, improved security isolation, and a new optional terminal environment module.

**Note: This flake is still in beta. Only remote mounting has received significant testing; all other features may be incomplete or unstable.**

## ✨ Added

### JSON-Driven Configuration (Now superseded by TOML in v0.3)

Introduced config.json as the single source of truth.

vars.nix now uses builtins.fromJSON to pass configuration values into the system.

Added config.sample.json template for newcomers.

### Optional Terminal Extras Module

A toggleable module (disabled by default) providing:

Zsh default shell with Oh My Posh (Dracula) and Oh My Zsh plugins.

Productivity tools: zoxide, fzf, direnv

Enhanced CLI tools: bat, eza, ripgrep, fd, delta, broot, duf, dust, etc.

Developer utilities: lazygit, gh, bottom, bandwhich, gping

Advanced shell enhancements: autosuggestions, syntax highlighting, improved history.


### Module & File Structure Improvements

Added top-level vars.nix (next to flake.nix) to cleanly propagate JSON config values.

Renamed modules/xen-orchestra.nix → modules/xoa.nix.

## 🚀 Improved

### SMB/CIFS Mounting

Automatic credential injection into mount commands.

Correct uid=xo / gid=xo ownership for remote mounts.

More reliable behavior under rootless XO operation.

### NFS Mounting

Auto-negotiates NFSv4/NFSv3.

Applies sensible defaults compatible with varied NFS servers.

Reduced edge-case failures and improved consistency.

### Rootless Xen Orchestra Execution

XO service now runs as a non-root user.

Mount commands are intercepted via a sudo wrapper that injects required parameters.

Wildcard sudo rules simplify upgrades by handling Nix store path changes.

### Security Isolation (Beta / Untested)

Security-related sandboxing has been added for testing, but requires further validation:

```
ProtectSystem = "strict" / "full"

ProtectHome = true

PrivateTmp = true

Minimal AmbientCapabilities

Empty CapabilityBoundingSet
```

⚠️ These hardening settings have not been fully tested under all XO workloads.

### Codebase Cleanup

Major reduction of obsolete or duplicate configurations across modules.

Consolidated filesystem and module declarations.

Simplified and commented capability configuration for clarity.

## ⚠️ Beta Status & Warnings

This project remains in beta.
The following areas are not fully tested and may fail unexpectedly:
- Rootless XO execution end-to-end
- NFS/SMB edge cases
- Systemd security hardening interactions
- Terminal extras module
- Various integration points across modules
- Only the remote mounting subsystem have received substantial validation.
