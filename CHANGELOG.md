<!-- SPDX-License-Identifier: Apache-2.0 -->
# Changelog

## v1.2.0 — Platform Dendritic Split

Date: 2026-02-27

This release includes a dendritic refactor,
XO module decomposition, and input compatibility updates.

### ✨ Added

- **Modular utility library** under `lib/utils/` (`get-option`, `options`, `module-lib`, `systemd`, `types`, `validators`)
- **XO module split** into focused files:
  - `options-base.nix`, `options-paths.nix`, `options-tls.nix`
  - `service/start-script.nix`
  - `storage/libvhdi-options.nix`, `storage/sudo-config.nix`, `storage/sudo-init.nix`
  - `tls-tmpfiles.nix`
- **Flake output split** into dedicated parts:
  - `parts/flake/nixos-modules.nix`
  - `parts/flake/outputs.nix`
  - `parts/flake/overlays.nix`
  - `parts/per-system/packages.nix`

### 🔄 Changed

- **Stack and feature key naming**: `system-*` → `platform-*`; appliance composition updated
- **parts/ layout flattened** from `parts/nix/*` into `parts/flake`, `parts/inputs`, `parts/registry`, and `parts/per-system`
- **Registry feature definitions** consolidated into `parts/registry/features.nix` (group sub-files removed)
- **XO/platform filenames normalized** (for example `state-version.nix`, `defaults.nix`, `config-link.nix`, `dev-tools.nix`, `tls-service.nix`)
- **Input sourcing and locks refreshed**:
  - `xen-orchestra-ce` moved from tagged source to beta tracking over HTTPS
  - lock updates include the 6.2.0 update cycle and nixpkgs/tooling refreshes
- **Docs/README/architecture** refreshed for the new structure and composition model

### 🗑️ Removed

- **Bundle-only collector modules** (`default.nix`) in platform and XO service/storage slices
- **Legacy monolithic XO options file** (`modules/features/xo/options.nix`)

### 🐛 Fixed

- **Deprecated Nix attr usage** replaced:
  - `final.system` → `final.stdenv.hostPlatform.system`
  - `pkgs.system` → `pkgs.stdenv.hostPlatform.system`

## v1.1.0 — Dendritic Feature Reorg

Date: 2026-01-27

This release reorganizes the module tree into clearer dendritic feature groups
and moves Xen guest integration into the core virtualization set.

### ✨ Added

- **virtualization/xen-guest.nix** in core (guest agent support)
- **foundation/** feature slice for shared module arguments

### 🔄 Changed

- **Module layout**: `modules/features/system/` → `modules/features/platform/`
- **Registry wiring** updated to match new feature categories
- **Appliance stack** now includes Xen guest integration by default (still gated by vars)
- **Docs/README** refreshed to describe the new layout
- **Dev tooling** moved out of core packages (codex, claude-code now live in system)

### 🗑️ Removed

- **system/virtualization/xen-guest.nix** (moved into core)

---

## v0.5 — Determinate Nix Migration & Xen VM Enhancements

Date: 2026-01-09

This release migrates to Determinate Nix, improves Xen VM hardware support, modernizes service configuration, and removes automatic update infrastructure.

### ✨ Added

- **hardware-xen.nix module** - Xen VM hardware configuration with /dev/xvda* device paths instead of UUIDs
  - Automatically maps Xen VM layout: xvda1 → /boot, xvda2 → /, xvda3 → swap
  - Uses lib.mkForce to override UUID-based hardware-configuration.nix
- **Systemd tmpfiles rules** for automatic directory creation:
  - Xen Orchestra symlink from /var/lib/xo/xen-orchestra to Nix store package
  - .ssh directory with proper permissions (0700) before authorized_keys creation

### 🔄 Changed

- **Migrated to Determinate Nix** - Removed obsolete configuration settings for cleaner deployment
- **Cachix integration** - Moved cachix configuration to system flake for better organizational structure
- **Redis → Valkey** - Updated services.redis.package = pkgs.valkey for Redis-compatible caching
- **Shell configuration** - Now based on vars.enableExtras instead of deprecated vars.shell variable
- **Swap disabled by default** - Improved performance for typical VM deployments

### 🗑️ Removed

- **Automatic updates infrastructure** - Removed all update modules and automation
  - Deleted modules/xo/updates/ directory (auto-upgrade.nix, common.nix, gc.nix, libvhdi.nix, nixpkgs.nix, xoa.nix)
  - Removed flake/apps.nix (only contained update-xo app)
  - Updates now managed via core git releases (stable/beta branches)
  - Future release will include TUI-based update management interface
  - Users should follow core repository releases and rebuild system manually

### 📚 Documentation

- Updated Xen VM hardware configuration documentation
- Clarified shell selection mechanism based on enableExtras flag
- Documented new update workflow via git releases

---

## v1.1 - Determinate Nix
## v1.0.0 — Milestone Release

Date: 2025-12-29

This milestone release marks nixoa-core reaching production-ready maturity with standardized option naming, modular architecture, and comprehensive feature completeness.

### 🎉 Milestone Achievements

- First stable 1.0.0 release
- Standardized options namespace (`nixoa.*`)
- Highly modular architecture
- Fully reproducible xen-orchestra build created as a nixpkg, pkg/xen-orchestra-ce/default.nix

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
- **configNixoaFile option** to link `config.nixoa.toml` to `/etc/xo-server/` for runtime config changes, config.nixoa.toml is an override file that operates on top of the default /etc/xo-server/config.toml, which you should not edit directly.
- **boot.nix module** with systemd-boot (endabled by default) + GRUB support with flexible boot configuration toggle
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
- `modules/home/home.nix` (migrated to system)
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

This major release refactors NiXOA Core from a runtime build system to a pure Nix-packaged solution using yarn2nix. This transformation improves reproducibility, enables binary caching, and reduces deployment time from 45+ minutes to seconds.

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
- Clean separation of build inputs (in nixoa-core) from user configuration (in system)
- Packages and utilities automatically available via nixoa-core's `_module.args`
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
- Updated xo-config.nix comment: "nixoa-config flake" → "system flake"
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
