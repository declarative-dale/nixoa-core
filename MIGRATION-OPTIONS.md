# NiXOA Options Architecture

## Overview

NiXOA CE now uses proper NixOS module options (`options.nixoa.*`) for configuration, following standard NixOS patterns. This provides:

- **Type safety**: Options enforce types at evaluation time
- **Better documentation**: Built-in option descriptions
- **Standard patterns**: Follows NixOS conventions
- **Clean separation**: nixoa-ce defines options, nixoa-ce-config provides values

## Architecture

### Before (Legacy)
```
nixoa.toml → vars.nix (parser) → vars object → specialArgs → modules use vars.*
```

### After (Current)
```
system-settings.toml → nixoa-config.nix (module) → config.nixoa.* → modules use config.nixoa.*
                                                         ↓
                                                  nixoa-ce defines options.nixoa.*
```

## Configuration Methods

### Method 1: Using nixoa-ce-config (Recommended)

This is the standard approach using the separate configuration flake:

1. **Edit configuration** in `/etc/nixos/nixoa-ce-config/system-settings.toml`:
   ```toml
   hostname = "my-xoa"
   username = "admin"
   sshKeys = ["ssh-ed25519 AAAAC3... user@host"]

   [xo]
   port = 80
   httpsPort = 443

   [xo.tls]
   enable = true
   autoGenerate = true
   ```

2. **Commit changes** (optional, for version control):
   ```bash
   cd /etc/nixos/nixoa-ce-config
   ./scripts/commit-config.sh "Update hostname"
   ```

3. **Rebuild system**:
   ```bash
   cd /etc/nixos/nixoa-ce
   sudo nixos-rebuild switch --flake .#nixoa
   ```

The `nixoa-ce-config/modules/nixoa-config.nix` module reads the TOML and sets `config.nixoa.*` values.

### Method 2: Pure Nix Configuration (Advanced)

For advanced users who prefer pure Nix, you can bypass TOML entirely:

1. **Create a custom configuration module** (e.g., `my-xoa-config.nix`):
   ```nix
   { config, ... }:
   {
     config.nixoa = {
       hostname = "my-xoa";
       admin = {
         username = "admin";
         sshKeys = [ "ssh-ed25519 AAAAC3... user@host" ];
       };
       xo = {
         port = 80;
         httpsPort = 443;
         tls = {
           enable = true;
           autoGenerate = true;
         };
       };
       # ... rest of config
     };
   }
   ```

2. **Import it in nixoa-ce/flake.nix**:
   ```nix
   modules = [
     ./hardware-configuration.nix
     ./modules
     ./my-xoa-config.nix  # Your custom config
   ];
   ```

3. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch --flake .#nixoa
   ```

### Method 3: Hybrid Approach

Use TOML for most settings, override specific values with Nix:

1. Keep `nixoa-ce-config` with TOML defaults
2. Add overrides in `flake.nix`:
   ```nix
   modules = [
     ./hardware-configuration.nix
     ./modules
     nixoa-config.nixosModules.default  # TOML defaults
     ({ config, ... }: {
       config.nixoa.xo.port = 8080;  # Override specific values
     })
   ];
   ```

## Configuration Reference

### Complete Options Tree

```nix
options.nixoa = {
  # System identification
  hostname = "nixoa";                    # String
  stateVersion = "25.11";                # String (DO NOT CHANGE after install)

  # Admin user
  admin = {
    username = "xoa";                    # String
    sshKeys = [];                        # List of strings
  };

  # Xen Orchestra
  xo = {
    host = "0.0.0.0";                    # String
    port = 80;                           # Integer (0-65535)
    httpsPort = 443;                     # Integer (0-65535)

    service = {
      user = "xo";                       # String
      group = "xo";                      # String
    };

    tls = {
      enable = true;                     # Boolean
      redirectToHttps = true;            # Boolean
      autoGenerate = true;               # Boolean
      dir = "/etc/ssl/xo";               # String (filesystem path)
      cert = "/etc/ssl/xo/certificate.pem";  # String
      key = "/etc/ssl/xo/key.pem";       # String
    };
  };

  # Storage
  storage = {
    nfs.enable = true;                   # Boolean
    cifs.enable = true;                  # Boolean
    vhd.enable = true;                   # Boolean
    mountsDir = "/var/lib/xo/mounts";    # String (filesystem path)
  };

  # Networking
  networking.firewall.allowedTCPPorts = [80 443 3389 5900 8012];  # List of integers

  # System
  timezone = "UTC";                      # String (e.g., "America/New_York")

  # Packages
  packages = {
    system.extra = [];                   # List of strings (nixpkgs attributes)
    user.extra = [];                     # List of strings
  };

  # Custom services
  services.definitions = {
    # Example: docker = { enable = true; enableOnBoot = true; };
  };

  # Terminal extras
  extras.enable = false;                 # Boolean

  # Updates configuration
  updates = {
    repoDir = "/etc/nixos/nixoa-ce";     # String

    monitoring = {
      notifyOnSuccess = false;           # Boolean
      email = { enable = false; to = "admin@example.com"; };
      ntfy = { enable = false; server = "https://ntfy.sh"; topic = "xoa-updates"; };
      webhook = { enable = false; url = ""; };
    };

    gc = { enable = false; schedule = "Sun 04:00"; keepGenerations = 7; };
    flake = { enable = false; schedule = "Sun 04:00"; autoRebuild = false; /* ... */ };
    nixpkgs = { enable = false; schedule = "Mon 04:00"; keepGenerations = 7; };
    xoa = { enable = false; schedule = "Tue 04:00"; keepGenerations = 7; };
    libvhdi = { enable = false; schedule = "Wed 04:00"; keepGenerations = 7; };
  };
};
```

### TOML → Nix Mapping

| TOML Path | Nix Path | Type |
|-----------|----------|------|
| `hostname` | `nixoa.hostname` | string |
| `username` | `nixoa.admin.username` | string |
| `sshKeys` | `nixoa.admin.sshKeys` | list of strings |
| `timezone` | `nixoa.timezone` | string |
| `xo.host` | `nixoa.xo.host` | string |
| `xo.port` | `nixoa.xo.port` | port (0-65535) |
| `xo.httpsPort` | `nixoa.xo.httpsPort` | port (0-65535) |
| `tls.enable` | `nixoa.xo.tls.enable` | boolean |
| `tls.redirectToHttps` | `nixoa.xo.tls.redirectToHttps` | boolean |
| `tls.autoGenerate` | `nixoa.xo.tls.autoGenerate` | boolean |
| `tls.dir` | `nixoa.xo.tls.dir` | string |
| `tls.cert` | `nixoa.xo.tls.cert` | string |
| `tls.key` | `nixoa.xo.tls.key` | string |
| `service.xoUser` | `nixoa.xo.service.user` | string |
| `service.xoGroup` | `nixoa.xo.service.group` | string |
| `storage.nfs.enable` | `nixoa.storage.nfs.enable` | boolean |
| `storage.cifs.enable` | `nixoa.storage.cifs.enable` | boolean |
| `storage.mountsDir` | `nixoa.storage.mountsDir` | string |
| `networking.firewall.allowedTCPPorts` | `nixoa.networking.firewall.allowedTCPPorts` | list of ports |
| `packages.system.extra` | `nixoa.packages.system.extra` | list of strings |
| `packages.user.extra` | `nixoa.packages.user.extra` | list of strings |
| `services.*` | `nixoa.services.definitions.*` | attrs |
| `extras.enable` | `nixoa.extras.enable` | boolean |
| `updates.*` | `nixoa.updates.*` | (nested structure) |
| `stateVersion` | `nixoa.stateVersion` | string |

## Querying Configuration

### View Option Definitions
```bash
# See option type
nix eval .#nixosConfigurations.nixoa.options.nixoa.hostname.type --json

# See option description
nix eval .#nixosConfigurations.nixoa.options.nixoa.hostname.description

# See all nixoa options
nix eval .#nixosConfigurations.nixoa.options.nixoa --apply 'opts: builtins.attrNames opts'
```

### View Current Configuration
```bash
# Check hostname value
nix eval .#nixosConfigurations.nixoa.config.nixoa.hostname --json

# Check all nixoa config
nix eval .#nixosConfigurations.nixoa.config.nixoa --json
```

### Verify Configuration Before Applying
```bash
# Dry-build (no changes)
sudo nixos-rebuild dry-build --flake .#nixoa

# Build without activating
sudo nixos-rebuild build --flake .#nixoa

# Test (activates but doesn't make it default)
sudo nixos-rebuild test --flake .#nixoa
```

## Custom Services

The `nixoa.services.definitions` option allows you to enable and configure NixOS services.

### TOML Method

**Simple enable**:
```toml
[services]
enable = ["docker", "tailscale"]
```

**Detailed configuration**:
```toml
[services.docker]
enable = true
enableOnBoot = true

[services.docker.autoPrune]
enable = true
dates = "weekly"

[services.tailscale]
enable = true
useRoutingFeatures = "both"
```

### Nix Method

```nix
{
  config.nixoa.services.definitions = {
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
    tailscale = {
      enable = true;
      useRoutingFeatures = "both";
    };
  };
}
```

These are merged into `config.services.*` by `system.nix`.

## Internal Architecture

### Option Definitions (nixoa-ce)

`modules/nixoa-options.nix` defines **all** `options.nixoa.*` with:
- Type enforcement (`types.str`, `types.port`, `types.bool`, etc.)
- Default values
- Descriptions and examples
- Validation rules

### Configuration Provider (nixoa-ce-config)

`modules/nixoa-config.nix`:
1. Reads `system-settings.toml`
2. Parses with `builtins.fromTOML`
3. Sets `config.nixoa.*` values as a NixOS module
4. Filters SSH keys (removes `_comment` and `_example` entries)
5. Parses custom services from `[services]` section

### Module Bridge (nixoa-ce/modules/system.nix)

`system.nix` bridges user-facing `config.nixoa.*` to internal module options:

```nix
# Bridge to internal xoa.* options
config.xoa = {
  enable = true;
  admin.user = config.nixoa.admin.username;
  xo = {
    user = config.nixoa.xo.service.user;
    port = config.nixoa.xo.port;
    ssl.enable = config.nixoa.xo.tls.enable;
    # ...
  };
};

# Bridge to updates module
config.updates = config.nixoa.updates;

# Merge custom services
config.services = config.nixoa.services.definitions // { /* built-in services */ };
```

## Best Practices

### 1. Use nixoa-ce-config for Deployment

- **Development**: Edit TOML directly
- **Production**: Use git-tracked nixoa-ce-config with commit history
- Benefit from version control and rollback capabilities

### 2. Validate Before Applying

Always dry-build first:
```bash
sudo nixos-rebuild dry-build --flake .#nixoa
```

### 3. Use Type-Safe Values

The option system catches errors early:
```nix
# ❌ Will fail evaluation (wrong type)
nixoa.xo.port = "80";  # String instead of port

# ✅ Correct
nixoa.xo.port = 80;    # Integer
```

### 5. Leverage Option Descriptions

```bash
# Read built-in documentation
nix eval .#nixosConfigurations.nixoa.options.nixoa.xo.tls.autoGenerate.description
```

## Troubleshooting

### Configuration Not Applied

1. **Check option is set**:
   ```bash
   nix eval .#nixosConfigurations.nixoa.config.nixoa.hostname --json
   ```

2. **Verify no evaluation errors**:
   ```bash
   sudo nixos-rebuild dry-build --flake .#nixoa
   ```

3. **Check flake inputs are up to date**:
   ```bash
   nix flake update
   ```

### Type Errors

```
error: A definition for option `nixoa.xo.port' is not of type `16 bit unsigned integer; between 0 and 65535 (both inclusive)'
```

**Solution**: Use correct type:
```nix
# ❌ Wrong
nixoa.xo.port = "8080";

# ✅ Correct
nixoa.xo.port = 8080;
```

### Missing Required Options

```
error: The option `nixoa.hostname' is used but not defined
```

**Solution**: Ensure nixoa-ce-config is imported or provide inline config:
```nix
config.nixoa.hostname = "nixoa";
config.nixoa.admin.username = "xoa";
```

### TOML Parse Errors

```
error: nixoa-ce-config: system-settings.toml is missing!
```

**Solution**: Ensure `system-settings.toml` exists in nixoa-ce-config:
```bash
cd /etc/nixos/nixoa-ce-config
ls -l system-settings.toml
```

## See Also

- [NixOS Manual: Modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
- [NixOS Module Options](https://search.nixos.org/options)
- [NiXOA CE Repository](https://codeberg.org/dalemorgan/nixoa-ce)
