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
- `flake.nix` - Wires in `nixoaCore.nixosModules.appliance` and your settings
- `scripts/` - Helper scripts (apply-config, commit-config, etc.)

**Who edits it:** You (regularly)

**How it changes:** Via git commits

### nixoa-vm (NiXOA Library)

**Location:** `/etc/nixos/nixoa-vm`

**Purpose:** The complete NiXOA implementation (modules, packages, build system)

**What's inside:**

#### modules/ - Feature Modules
```
modules/
└── features/
    ├── system/           - System features (identity, boot, users, networking, packages, services)
    ├── virtualization/   - VM hardware features (Xen overrides)
    ├── xo/               - XO features (options, service, config, storage, tls, cli, extras)
    └── shared/args.nix    - Shared module args (vars, nixoaUtils)
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

#### parts/ - Flake Composition (Dendritic)
```
parts/
├── nix/inputs/         - Input declarations
├── nix/flake-parts/    - flake-parts + flake-file wiring
├── nix/registry/       - Feature registry + stacks
├── features/           - Registry-driven module entrypoints
└── flake/              - Exports + per-system outputs
```

#### flake.nix - Flake Entry Point (generated)
```
Exports:
- nixosModules.appliance - Full NiXOA appliance stack
- nixosModules.system    - Base system stack
- nixosModules.xo        - XO feature stack
- nixosModules.*         - Individual feature modules
- overlays.nixoa         - XO/libvhdi overlay
- packages.x86_64-linux  - XO and libvhdi packages
- registry               - Feature registry (modules + stacks)
- lib                    - Composition helpers
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
5. user-config flake imports the NiXOA core flake and selects nixosModules.appliance
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

### System Features (No XO Logic)

These modules live under `modules/features/system/`:

- **system/identity.nix** - Hostname, locale, shells, state version
- **system/boot.nix** - Boot loader, initrd, kernel support
- **system/users.nix** - User accounts, groups, SSH access, PAM
- **system/networking.nix** - Network defaults, firewall, NFS client
- **system/packages.nix** - System packages, Nix configuration, garbage collection
- **system/services.nix** - systemd services, monitoring, logging

Could be used for any NixOS system.

### Virtualization Features

These modules live under `modules/features/virtualization/`:

- **virtualization/xen-hardware.nix** - Xen guest hardware defaults

### XO Features

These modules live under `modules/features/xo/`:

- **xo/options.nix** - XO option schema (nixoa.xo.*)
- **xo/config.nix** - Generates `/etc/xo-server/config.nixoa.toml`
- **xo/service.nix** - XO service (Node.js, packages, systemd service)
- **xo/storage.nix** - NFS/CIFS mounts, VHD support
- **xo/tls.nix** - Auto-generated TLS certificates
- **xo/cli.nix** - CLI utilities for NiXOA
- **xo/extras.nix** - Optional terminal enhancements (zsh, oh-my-posh, tools)

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
   └─ Flows to all nixoa-vm features
      ├─ system/identity.nix uses: hostname, timezone, stateVersion
      ├─ system/boot.nix uses: boot loader and initrd settings
      ├─ system/users.nix uses: username, sshKeys
      ├─ system/networking.nix uses: firewall and network defaults
      ├─ system/packages.nix uses: system packages
      ├─ virtualization/xen-hardware.nix uses: Xen guest hardware defaults
      ├─ xo/service.nix uses: xo.*, storage.*
      ├─ xo/storage.nix uses: storage.* settings
      ├─ xo/tls.nix uses: tls settings
      ├─ xo/extras.nix uses: extras settings
      └─ ... (other features use relevant settings)
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
nixoa-vm/flake.nix (generated)
└─ nixosModules.appliance = {...modules...}
   │
   ├─ parts/nix/registry/features.nix
   │  └─ stacks.appliance = [
   │       "system-identity"
   │       "system-boot"
   │       "system-users"
   │       "system-networking"
   │       "system-packages"
   │       "system-services"
   │       "virtualization-xen-hardware"
   │       "xo-options"
   │       "xo-config"
   │       "xo-service"
   │       "xo-storage"
   │       "xo-tls"
   │       "xo-cli"
   │       "xo-extras"
   │     ]
   │
   ├─ parts/nix/flake-parts/lib.nix
   │  └─ mkFeatureModule/mkStackModule helpers
   │
   ├─ parts/flake/exports.nix
   │  └─ Builds nixosModules.* from registry + helpers
   │
   └─ modules/features/
      ├─ system/identity.nix
      ├─ system/boot.nix
      ├─ system/users.nix
      ├─ system/networking.nix
      ├─ system/packages.nix
      ├─ system/services.nix
      ├─ virtualization/xen-hardware.nix
      └─ xo/{options,config,service,storage,tls,cli,extras}.nix
   │
   └─ Available to user-config/flake.nix as nixoaCore.nixosModules.appliance
```

## Options System

NiXOA defines options in modules:

```
nixoa-vm/modules/features/xo/options.nix
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
