# Architecture Guide

Understand how NiXOA is structured and how the pieces work together.

## Two-Repository System

NiXOA uses a clean separation between implementation and configuration:

```
┌─────────────────────────────────────┐
│  ~/user-config  (YOUR REPOSITORY)   │
│  - Where you make changes           │
│  - Your system settings             │
│  - Your personal configuration      │
└────────────┬────────────────────────┘
             │ imports modules from
             ▼
┌─────────────────────────────────────────────────────────┐
│  /etc/nixos/nixoa-vm  (NiXOA LIBRARY - Immutable)       │
│  - Core NixOS modules                                   │
│  - Xen Orchestra integration                            │
│  - Build system and packages                            │
│  - Never edited manually, only updated via git          │
└─────────────────────────────────────────────────────────┘
```

## Repository Roles

### user-config (Your Repository)

**Location:** `~/user-config`

**Purpose:** Your personal system configuration and deployment entry point

**What's inside:**
- `configuration.nix` - Your system settings
- `hardware-configuration.nix` - Your hardware details (one-time)
- `config.nixoa.toml` - Optional XO server overrides
- `flake.nix` - Imports nixoa-vm modules + combines everything
- `scripts/` - Helper scripts (apply-config, commit-config, etc.)

**Who edits it:** You (regularly)

**How it changes:** Via git commits

### nixoa-vm (NiXOA Library)

**Location:** `/etc/nixos/nixoa-vm`

**Purpose:** The complete NiXOA implementation (modules, packages, build system)

**What's inside:**

#### modules/ - NixOS Modules
```
modules/
├── core/              - System-level modules (no XO-specific logic)
│   ├── base.nix       - System ID, locale, kernel
│   ├── boot.nix       - Boot loader configuration
│   ├── users.nix      - User accounts and SSH
│   ├── networking.nix - Network and firewall
│   ├── packages.nix   - System packages
│   └── services.nix   - System services
│
└── xo/               - Xen Orchestra modules
    ├── xoa.nix       - Core XO service
    ├── xo-config.nix - Generate config file
    ├── storage.nix   - NFS/CIFS/VHD support
    ├── libvhdi.nix   - VHD library
    ├── autocert.nix  - Auto TLS certificates
    ├── updates/      - Update system
    │   ├── gc.nix
    │   ├── xoa.nix
    │   └── nixpkgs.nix
    ├── extras.nix    - Terminal enhancements
    └── nixoa-cli.nix - CLI tools
```

#### pkgs/ - Package Definitions
```
pkgs/
├── xen-orchestra-ce/  - XO packaged with yarn2nix
└── libvhdi/           - VHD library package
```

#### lib/ - Utility Functions
```
lib/
└── utils.nix - Shared helper functions (getOption, etc.)
```

#### flake.nix - Flake Entry Point
```
Exports:
- nixosModules.default   - All NiXOA modules
- packages.x86_64-linux  - XO and libvhdi packages
- lib - Utility functions
```

**Who edits it:** NiXOA developers/contributors (rarely)

**How it changes:** Via git commits, pulled from upstream

## Data Flow: How Configuration Becomes System

```
1. You edit ~/user-config/configuration.nix
   ↓
2. ./scripts/apply-config "message"
   ↓
3. Git commits your changes
   ↓
4. nixos-rebuild reads ~/user-config/flake.nix
   ↓
5. flake.nix imports /etc/nixos/nixoa-vm/flake.nix
   ↓
6. NiXOA modules receive your settings via specialArgs
   ↓
7. Modules generate NixOS configuration
   ↓
8. NixOS evaluates full system configuration
   ↓
9. Nix derivations built (packages, services, files)
   ↓
10. System switched to new generation
    ↓
11. Services restarted if needed
    ↓
12. Your system now runs new configuration
```

## Module Organization

### Core Modules (No XO Logic)

These modules are independent of Xen Orchestra:

- **base.nix** - System hostname, locale, kernel modules
- **boot.nix** - Boot loader (systemd-boot or GRUB)
- **users.nix** - User accounts, groups, SSH access, PAM
- **networking.nix** - Network interfaces, firewall rules, NFS support
- **packages.nix** - System packages, Nix configuration, garbage collection
- **services.nix** - systemd services, monitoring, logging

Could be used for any NixOS system.

### XO-Specific Modules

These implement Xen Orchestra functionality:

- **xoa.nix** - Core XO service (Node.js, packages, systemd service)
- **xo-config.nix** - Generates `/etc/xo-server/config.nixoa.toml`
- **storage.nix** - NFS mount support, CIFS mount support, VHD library setup
- **libvhdi.nix** - VHD (Virtual Hard Disk) support
- **autocert.nix** - Auto-generated TLS certificates
- **updates/** - Automated update system (garbage collection, package updates, XO updates)
- **extras.nix** - Optional terminal enhancements (zsh, oh-my-posh, tools)
- **nixoa-cli.nix** - CLI utilities for NiXOA

## Configuration Inheritance

Your configuration flows through the system:

```
~/user-config/configuration.nix
│
├─ userSettings
│  └─ Flows to home.nix (Home Manager)
│     └─ Configures user environment (shell, packages, dotfiles)
│
└─ systemSettings
   └─ Flows to all nixoa-vm modules
      ├─ core/base.nix uses: hostname, stateVersion
      ├─ core/users.nix uses: username, sshKeys
      ├─ core/networking.nix uses: networking, firewall
      ├─ xo/xoa.nix uses: xo.*, storage.*, updates.*
      ├─ xo/extras.nix uses: extras.enable
      └─ ... (other modules use relevant settings)
```

## Build System (yarn2nix)

Xen Orchestra is packaged using yarn2nix:

```
xen-orchestra (source repository)
│
├─ yarn.lock (dependency list)
│
└─ pkgs/xen-orchestra-ce/default.nix
   ├─ Parses yarn.lock
   ├─ Downloads dependencies
   ├─ Builds XO monorepo
   ├─ Applies patches
   ├─ Runs tests
   └─ Creates /nix/store/...-xo-ce derivation
```

Benefits:
- Reproducible builds (same inputs = same output)
- Binary cache support (pre-built packages)
- Fast deployments (no runtime compilation)
- Atomic updates (rollback capability)

## File Organization

### System Configuration

```
/etc/
├── nixos/
│   ├── nixoa/
│   │   └── nixoa-vm/            ← NiXOA modules (from repo)
│   └── hardware-configuration.nix ← Generated during NixOS install
│
├── xo-server/
│   └── config.nixoa.toml        ← Generated from your configuration
│
└── ssl/xo/
    ├── certificate.pem          ← TLS certificate
    └── key.pem                  ← TLS key
```

### XO Data

```
/var/lib/xo/
├── app/                    ← Built XO application
├── data/                   ← XO database and state
├── mounts/                 ← Remote storage mounts (NFS, CIFS)
└── tmp/                    ← Temporary files
```

### Redis (Caching)

```
/run/redis-xo/
└── redis.sock             ← Unix socket (not network exposed)
```

### Logs

```
journalctl (systemd journal)
└── Multiple services log here:
    - xo-server.service
    - xo-build.service
    - redis-xo.service
```

## Service Architecture

```
systemd (init system)
│
├─ xo-server.service
│  └─ Runs Node.js with XO code
│     └─ Connects to Redis via /run/redis-xo/redis.sock
│
├─ redis-xo.service
│  └─ Runs Redis caching server
│
└─ nginx (optional)
   └─ Reverse proxy / SSL termination
```

## Module Imports

How modules are discovered and loaded:

```
nixoa-vm/flake.nix
└─ nixosModules.default = {...modules...}
   │
   ├─ modules/default.nix
   │  └─ Imports all modules explicitly:
   │     ├─ ./core/base.nix
   │     ├─ ./core/boot.nix
   │     ├─ ./core/users.nix
   │     ├─ ./core/networking.nix
   │     ├─ ./core/packages.nix
   │     ├─ ./core/services.nix
   │     ├─ ./xo/xoa.nix
   │     ├─ ./xo/xo-config.nix
   │     ├─ ./xo/storage.nix
   │     ├─ ./xo/libvhdi.nix
   │     ├─ ./xo/autocert.nix
   │     ├─ ./xo/updates/common.nix
   │     ├─ ./xo/updates/gc.nix
   │     ├─ ./xo/updates/xoa.nix
   │     ├─ ./xo/updates/nixpkgs.nix
   │     ├─ ./xo/updates/libvhdi.nix
   │     ├─ ./xo/extras.nix
   │     └─ ./xo/nixoa-cli.nix
   │
   └─ Available to user-config/flake.nix as nixoa-vm.nixosModules.default
```

## Options System

NiXOA defines options in modules:

```
nixoa-vm/modules/xo/xoa.nix
│
└─ options.nixoa.xo = {
   │  port = mkOption { ... };
   │  host = mkOption { ... };
   │  tls.enable = mkOption { ... };
   └─ ... (many more options)
```

You set values in your configuration:

```
~/user-config/configuration.nix
│
└─ config.nixoa.xo = {
      port = 80;
      host = "0.0.0.0";
      tls.enable = true;
   };
```

The module system merges them and validates types.

## Version Control Strategy

### nixoa-vm Repository

```
Origin: https://codeberg.org/nixoa/nixoa-vm.git
Branches:
├─ main     ← Stable releases
└─ beta     ← Development/experimental
```

You pull updates:
```bash
cd /etc/nixos/nixoa-vm
git pull origin main  # or beta
```

### user-config Repository

```
Origin: https://codeberg.org/nixoa/user-config.git
Local: ~/user-config
Branches:
├─ main     ← Default
└─ (your custom branches as needed)
```

You commit locally:
```bash
cd ~/user-config
git commit -m "Updated configuration"
```

## Key Design Principles

1. **Clear Separation** - Configuration (user-config) vs Implementation (nixoa-vm)
2. **Reproducibility** - Same configuration always produces same system
3. **Version Control** - All changes tracked in git
4. **Modularity** - Each concern in its own module
5. **Declarative** - Describe desired state, not steps to achieve it
6. **Immutability** - /nix/store packages are immutable
7. **Atomicity** - Updates are all-or-nothing with rollback

## Building From Scratch

When you run `nixos-rebuild`:

```
1. Read configuration.nix
2. Combine with nixoa-vm modules
3. Evaluate all Nix expressions
4. Build derived packages
   ├─ XO package (if not cached)
   ├─ System packages
   ├─ Configuration files
   └─ Systemd services
5. Create system closure (all dependencies)
6. Copy to /nix/store
7. Make bootable
8. Switch to new generation
```

First build takes 10-30 minutes. Subsequent builds cache results.

## See Also

- [Configuration Guide](./configuration.md) - How to configure
- [Operations Guide](./operations.md) - How to run it
- [Installation Guide](./installation.md) - How to install
