<!-- SPDX-License-Identifier: Apache-2.0 -->
# Changelog

## v0.8 - NiXOA-VM Appliance Mode

**Release Date:** December 24, 2025

### 🎉 Major Architectural Change: Module Library Migration

This release represents a fundamental restructuring of the NixOA project, inverting the dependency between `nixoa-vm` and `user-config` flakes for a cleaner, more maintainable architecture.

---

### What Changed

#### Before (v0.x - Inverted Architecture)
```
nixoa-vm (entry point)
├── Exports: nixosConfigurations
├── Imports: user-config
└── Rebuild location: /etc/nixos/nixoa/nixoa-vm

user-config (data export)
├── Exports: configuration data only
├── Contains: configuration.nix, config.nixoa.toml
└── Location: /etc/nixos/nixoa/user-config
```

#### After (v0.8 - Correct Architecture)
```
user-config (entry point) ✅
├── Exports: nixosConfigurations
├── Imports: nixoa-vm as module library
├── Contains: modules/home.nix, configuration.nix
└── Rebuild location: ~/user-config

nixoa-vm (module library) ✅
├── Exports: nixosModules.default
├── Contains: core/, xo/ system modules (immutable)
├── Location: /etc/nixos/nixoa/nixoa-vm (git-managed)
└── Updated via: git pull only
```

---

### nixoa-vm Flake Changes

#### ✨ New: Module Library Exports
- **`nixosModules.default`** - Primary export bundling all system modules (core/, xo/)
- Automatically imports all modules except home/ (now in user-config)
- Makes flake sources (xoSrc, libvhdiSrc) available to modules
- Can be imported by user-config: `nixoa-vm.nixosModules.default`

#### 🔄 Removed: Configuration Entry Point
- `nixosConfigurations.*` output removed (responsibility moved to user-config)
- No longer consumes `nixoa-config` input
- No longer imports hardware-configuration.nix directly
- Simplified to pure module provider (no configuration logic)

#### 📝 Updated: Development Shell
- Updated devShell messages to reflect module library purpose
- Clarified that configuration is in ~/user-config, not here
- Added usage instructions for module imports

#### 📍 Updated: Installer Script
- Changed user-config installation location from `/etc/nixos/nixoa/user-config` to `~/user-config`
- Simplified installer to clone both flakes to their new locations
- Updated rebuild command examples to reference new entry point

#### 🔧 Updated: Update Module
- Changed `updates.repoDir` default from `/etc/nixos/xoa-flake` to `~/user-config`
- Rebuild commands now target correct entry point automatically
- Tilde expansion works with admin user home directory

#### 📚 Updated: Documentation
- README.md updated with new installation flow
- Installation steps now show correct directory structure
- Examples reflect rebuilding from ~/user-config
- Clarified that nixoa-vm is immutable module library

---

### How This Affects You

#### Installation Workflow
**Old (v0.x):**
```bash
sudo mkdir -p /etc/nixos/nixoa
sudo git clone https://codeberg.org/nixoa/nixoa-vm.git /etc/nixos/nixoa/nixoa-vm
sudo git clone https://codeberg.org/nixoa/user-config.git /etc/nixos/nixoa/user-config
# Edit /etc/nixos/nixoa/user-config/configuration.nix
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#hostname
```

**New (v0.8):**
```bash
bash <(curl -fsSL https://codeberg.org/nixoa/nixoa-vm/raw/main/scripts/xoa-install.sh)
# Installer clones both automatically:
# - nixoa-vm → /etc/nixos/nixoa/nixoa-vm (immutable)
# - user-config → ~/user-config (your home directory)

# Edit ~/user-config/configuration.nix
cd ~/user-config
sudo nixos-rebuild switch --flake .#hostname
```

#### Rebuild Workflow
**Old:**
```bash
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#<hostname>
```

**New:**
```bash
cd ~/user-config  # Your personal configuration
sudo nixos-rebuild switch --flake .#<hostname>
```

#### File Organization

##### nixoa-vm (Immutable)
```
/etc/nixos/nixoa/nixoa-vm/
├── flake.nix              # Module library exports
├── modules/
│   ├── core/              # System modules
│   ├── xo/                # XO service modules
│   └── home/              # REMOVED (moved to user-config)
├── scripts/               # Setup and helper scripts
└── README.md              # Installation guide
```

##### user-config (Your Configuration)
```
~/user-config/
├── flake.nix              # Entry point (exports nixosConfigurations)
├── configuration.nix      # Your settings
├── modules/
│   └── home.nix           # Home-manager config (NEW location)
├── hardware-configuration.nix
├── config.nixoa.toml
└── scripts/               # Helper scripts
```

---

### Benefits of This Architecture

#### ✅ Clearer Separation of Concerns
- **nixoa-vm**: Immutable system module definitions
- **user-config**: User configuration and settings

#### ✅ Better Maintainability
- nixoa-vm updates via git (controlled)
- user-config changes are personal (isolated)
- No circular dependencies

#### ✅ Improved User Experience
- All edits happen in one place: `~/user-config/`
- Rebuild command runs from configuration directory (intuitive)
- Home-manager config with your settings, not system-wide

#### ✅ Easier System Updates
- Update nixoa-vm: `cd /etc/nixos/nixoa/nixoa-vm && sudo git pull`
- Update user-config: `cd ~/user-config && git pull`
- Rebuild from user-config: automatic module import from nixoa-vm

---

### Breaking Changes ⚠️

This is a **major version release** with breaking changes. Existing installations will not work with v1.0 without updates.

#### What Breaks
- ❌ Old flake.lock files invalid (nixoa-config input removed)
- ❌ Cannot rebuild from `/etc/nixos/nixoa/nixoa-vm` anymore
- ❌ user-config cannot be at `/etc/nixos/nixoa/user-config` (must be ~/user-config)
- ❌ home-manager config location changed (moved to user-config/modules/home.nix)

#### Migration Path

For **fresh installations**, use the new installer (recommended):
```bash
bash <(curl -fsSL https://codeberg.org/nixoa/nixoa-vm/raw/main/scripts/xoa-install.sh)
```

---

### Module Library Usage

If you want to extend NixOA with custom flakes, you can now import nixoa-vm as a module library:

```nix
# In your flake.nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  nixoa-vm = {
    url = "path:/etc/nixos/nixoa/nixoa-vm";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};

outputs = { self, nixpkgs, nixoa-vm }:
{
  nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      nixoa-vm.nixosModules.default
      # Your custom modules here
    ];
  };
};
```

---

### Technical Details

#### Flake Input Resolution
- **nixoa-vm input path**: `path:/etc/nixos/nixoa/nixoa-vm`
- **home-manager source**: Follows from nixoa-vm (`home-manager.follows = "nixoa-vm/home-manager"`)
- **nixpkgs consistency**: Both flakes follow the same nixpkgs (25.11 release branch)

### Module Bundling
- **Bundle mechanism**: `modules/bundle.nix` dynamically discovers all .nix files
- **Exclusions**: `bundle.nix`, `default.nix`, and `home/` directory
- **Imports**: Automatic recursive import from subdirectories (core/, xo/)

### Home-Manager Integration
- **Location**: Moved from `nixoa-vm/modules/home/home.nix` to `user-config/modules/home.nix`
- **Configuration**: Still integrated as NixOS module (single rebuild command)
- **Specialization**: Receives userSettings and systemSettings via extraSpecialArgs
---
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
