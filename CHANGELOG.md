<!-- SPDX-License-Identifier: Apache-2.0 -->
# Changelog

## v1.0.0 — Milestone Release

Date: 2025-12-29

This milestone release marks nixoa-vm reaching production-ready maturity with standardized option naming, modular architecture, and comprehensive feature completeness.

### 🎉 Milestone Achievements

- First stable 1.0.0 release
- Standardized options namespace (`nixoa.*`)
- Complete modular architecture
- Production-ready configuration system

### ⚠️ BREAKING CHANGES

All options renamed from `xoa.*` to `nixoa.*` namespace:

- `config.xoa.enable` → `config.nixoa.xo.enable`
- `config.xoa.xo.*` → `config.nixoa.xo.*`
- `config.xoa.storage.*` → `config.nixoa.storage.*`
- `config.xoa.autocert.*` → `config.nixoa.autocert.*`
- `config.xoa.extras` → `config.nixoa.extras`

**Migration required** for all existing configurations.

### ✨ Added

- **Snitch network monitor** package for real-time connection monitoring
- **configNixoaFile option** to link `config.nixoa.toml` to `/etc/xo-server/` for runtime config changes
- **boot.nix module** with systemd-boot/GRUB support and flexible boot configuration toggle
- **Modular updates system** - split `updates.nix` into `updates/` directory:
  - `updates/common.nix` - shared update functionality
  - `updates/auto-upgrade.nix` - system auto-upgrade scheduling
  - `updates/gc.nix` - garbage collection
  - `updates/xoa.nix` - Xen Orchestra updates
  - `updates/nixpkgs.nix` - nixpkgs package updates
  - `updates/libvhdi.nix` - libvhdi library updates
- Made `config.nixoa.toml` readable by `xo` user for runtime configuration access
- Added explicit module imports replacing dynamic discovery

### 🔄 Changed

- Replaced dynamic module bundling with explicit imports in `modules/default.nix`
- Updated `autocert.nix` to use local variables (`httpCfg`, `xoUser`, `xoGroup`)
- Simplified boot configuration logic (removed redundant conditionals)
- Enhanced package references to use `nixoaPackages.xo-ce` directly
- Updated all module option references to new `nixoa.*` namespace
- Improved Node.js v20 → v24 migration in xen-orchestra package

### 🗑️ Removed

- `bundle.nix` (replaced with explicit imports)
- `modules/home/home.nix` (migrated to user-config)
- `integration.nix` module (functionality distributed)
- Redundant permission checks

### 🐛 Fixed

- Service environment path configuration
- Systemd working directory conflicts
- Package reference scoping issues during module evaluation
- Broken symlinks in xen-orchestra build process
- Git repository handling in Nix sandbox
- Dev dependencies installation in yarn build
- Various syntax errors in configuration files

### 📚 Documentation

- Updated all option references throughout documentation
- Updated CONFIGURATION.md with new option names
- Updated troubleshooting guides with correct file paths

---

## v0.9 — Architecture Refactoring (yarn2nix Packaging & Build System Separation)

Date: 2025-12-24

This major release refactors NixOA-VM from a runtime build system to a pure Nix-packaged solution using yarn2nix. This transformation improves reproducibility, enables binary caching, and reduces deployment time from 45+ minutes to seconds.

### ✨ Added

**Phase 1: Package Definitions**
- Xen Orchestra packaged via yarn2nix in `pkgs/xoa/default.nix` with full Yarn workspace support
- libvhdi extracted as standalone package in `pkgs/libvhdi/default.nix`
- Packages exposed via flake outputs with overlay support for easy integration
- Package verification and artifact validation in build process

**Phase 2: Centralized Utilities**
- New `lib/utils.nix` with reusable helper functions for common patterns
- `getOption` function for safe nested attribute access with defaults
- Helper functions for common Nix patterns: `mkDefaultOption`, `mkEnableOpt`, `mkSystemdService`
- Path and port validation helpers for improved type safety

**Phase 4: Flake Integration**
- Clean separation of build inputs (in nixoa-vm) from user configuration (in user-config)
- Packages and utilities automatically available via nixoa-vm's `_module.args`
- Simplified flake inheritance model with zero duplication

### 🔄 Changed

**Phase 3: Module Refactoring (268 lines removed)**

1. **xoa.nix (43% reduction - 618 → 352 lines)**
   - Removed 136-line buildXO script - build now happens at package time
   - Removed 33-line checkXORebuildNeeded script - rebuild detection obsolete
   - Removed nodeWithFuse wrapper - native modules pre-patched in package
   - Removed xo-build.service systemd service - no runtime build needed
   - Updated startXO to use packaged XOA from `/nix/store` (immutable)
   - Removed 4 obsolete options: `appDir`, `webMountDir`, `webMountDirv6`, `buildIsolation`
   - Updated xo-server.service to remove dependency on xo-build.service
   - Updated WorkingDirectory to immutable /nix/store path
   - Removed LD_LIBRARY_PATH (native modules pre-patched)
   - Removed appDir from ReadWritePaths

2. **libvhdi.nix (64% reduction - 112 → 40 lines)**
   - Removed 64-line inline derivation - now in pkgs/libvhdi/default.nix
   - Removed fallback fetchurl logic - source provided by flake inputs
   - Updated package default to reference nixoaPackages.libvhdi

3. **Core Module Utility Refactoring (54 lines removed)**
   - All 6 core modules now use centralized `getOption` from lib/utils.nix
   - Eliminated 9-line `get` function duplication in each module
   - Updated modules: base.nix, networking.nix, packages.nix, services.nix, users.nix, integration.nix
   - Added nixoaUtils to function parameters across all affected modules

**Documentation Updates**
- Updated CONFIGURATION.md: system-settings.toml → configuration.nix, xo-server-settings.toml → config.nixoa.toml
- Updated troubleshooting-cheatsheet.md with new file references
- Updated xo-config.nix comment: "nixoa-config flake" → "user-config flake"
- Updated all configuration examples to reflect new Nix-based configuration format

### ✨ Benefits

**For Users**
- 10-100x faster deploys: No 45-minute build on every `nixos-rebuild`
- Binary cache eligible: XOA can be pre-built and cached
- Reproducible builds: Same inputs → identical package hash
- Atomic updates: Switch XO versions instantly via rollback

**For Developers**
- Cleaner architecture: Build (flake) vs. runtime (modules) separation
- 322 lines of code removed (build scripts + duplicated functions)
- Better testability: Packages can be tested independently
- Maintainability: Single source of truth for utilities

**For the Project**
- Nix best practices: Proper flake structure, pure derivations
- Upstream-friendly: XOA package could be contributed to nixpkgs
- CI/CD ready: Packages can be built and cached in CI

### 🔧 Implementation Details

**Phase 1 - Package Definitions**
- Created XOA package with yarn2nix using workspace dependencies
- Applied upstream patches (SMB handler, TypeScript generics) in preBuild
- Native module patching with patchelf in postInstall
- Build artifact verification with explicit error messages
- libvhdi extracted with full autoconf configuration

**Phase 2 - Utils Library**
- Nested attribute access with proper default handling
- Helper utilities for option definitions and service templates
- Path and port validation to catch configuration errors early
- Imported and exported via flake as nixoaUtils

**Phase 3 - Module Refactoring**
- xoa.nix: Removed all runtime build logic, uses packaged XOA
- libvhdi.nix: Package default references nixoaPackages.libvhdi
- Core modules: Replace duplicated `get` function with `getOption` utility
- integration.nix: Updated all `get` calls to `getOption systemSettings`

**Phase 4 - Flake Integration**
- user-config: Removed unnecessary xoSrc/libvhdiSrc from specialArgs
- nixoa-vm: Provides nixoaPackages and nixoaUtils via _module.args
- Clean separation: Flake inputs managed by nixoa-vm only

**Phase 5 - Documentation Cleanup**
- Systematic search and replace of stale file name references
- Updated documentation to reflect new configuration format
- Module comments updated to reflect new architecture

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
