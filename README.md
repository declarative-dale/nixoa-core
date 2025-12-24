<!-- SPDX-License-Identifier: Apache-2.0 -->
# NiXOA: Xen Orchestra Community Edition on NixOS

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](./LICENSE)

An experimental Xen Orchestra Community Edition flake for NixOS VMs in XCP-NG.

> **⚠️ Important Disclaimer**
>
> This project is **experimental** and intended for **homelab use only**. It is **NOT production-ready** and is **NOT supported by Vates**.
>
> **For production environments:** Professional organizations should purchase the official [Xen Orchestra Appliance (XOA)](https://xen-orchestra.com/) from Vates, which includes:
> - Pre-compiled, tested builds
> - Official technical support
> - Production-grade reliability
> - Regular security updates and patches
> - Professional SLA options

## Features

- ✅ Build from pinned GitHub source
- ✅ HTTPS with auto-generated self-signed certificates
- ✅ Rootless operation (dedicated `xo` service account)
- ✅ NFS/CIFS remote mounting with VHD/VHDX support
- ✅ Dedicated Redis instance (Unix socket)
- ✅ SSH-only admin access
- ✅ Automated updates with generation management
- ✅ Comprehensive logging and monitoring

---

## Quick Start

> **Important:** NiXOA uses a **separate configuration flake** (`user-config`) that is the primary entry point. You will run system rebuilds from `~/user-config` (your home directory), while `nixoa-vm` remains immutable and git-managed in `/etc/nixos/nixoa/nixoa-vm`.


### Automated Installation (Untested)

The easiest way to get started is to use the bootstrap installer. It handles everything automatically:

```bash
# Run as a regular user (NOT root)
bash <(curl -fsSL https://codeberg.org/nixoa/nixoa-vm/raw/main/scripts/xoa-install.sh)
```
### Manual Installation (Tested)
Or clone the repo first and run locally:

```bash
git clone https://codeberg.org/nixoa/nixoa-vm.git
cd nixoa-vm/scripts
bash xoa-install.sh
```

The installer will:
1. Clone the nixoa-vm flake to `/etc/nixos/nixoa/nixoa-vm` (immutable module library)
2. Clone user-config flake to `~/user-config` (your configuration entry point)
3. Generate initial configuration files if missing (configuration.nix, config.nixoa.toml)
4. Copy/generate your hardware configuration to `~/user-config`
5. Initialize git repository for version control
6. Provide next steps for customization and first rebuild

### Manual Installation

If you prefer more control, follow these steps:

#### 1. Clone Repositories

```bash
# Create nixos config directory for module library
sudo mkdir -p /etc/nixos/nixoa
cd /etc/nixos/nixoa

# Clone module library (nixoa-vm) - this is immutable, only updated via git
sudo git clone https://codeberg.org/nixoa/nixoa-vm.git

# Clone user configuration to home directory - this is where YOU make changes
git clone https://codeberg.org/nixoa/user-config.git ~/user-config
```

- **nixoa-vm** in `/etc/nixos/nixoa/nixoa-vm` - immutable module library, system-wide
- **user-config** in `~/user-config` - your personal configuration, entry point for rebuilds

#### 2. Configure System

Edit your user configuration:

```bash
cd ~/user-config
nano configuration.nix
```

**Required changes in `systemSettings`:**
- `hostname` - Your system's hostname
- `username` - Admin user for SSH access
- `sshKeys` - Your SSH public key(s)

**Optional changes:**
- `xo.port` / `xo.httpsPort` - Change default XO ports
- `storage.*` - Enable/disable NFS and CIFS support
- `userSettings.extras.enable` - Enhanced terminal experience with zsh
- `userSettings.packages.extra` - Additional user packages
- `systemSettings.packages.system.extra` - System-wide packages

#### 3. Apply Configuration

After editing, apply your configuration:

```bash
cd ~/user-config
./scripts/apply-config.sh "Initial deployment"
```

This will:
1. Commit your configuration changes to git
2. Run `sudo nixos-rebuild switch` with your configured hostname
3. Apply all settings to your system

Alternatively, for more control:

```bash
# Just commit without rebuilding
./scripts/commit-config.sh "Initial configuration"

# Later, rebuild manually
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#<hostname> -L
```

Replace `<hostname>` with the `hostname` value in `~/user-config/configuration.nix`.

### 4. Access Xen Orchestra

```
HTTPS: https://your-server-ip/
HTTP:  http://your-server-ip/
V6 UI: https://your-server-ip/v6  (new interface)

Default credentials (change immediately):
  Username: admin@admin.net
  Password: admin
```

---

## Advanced: Using as a Flake Input

If you have an existing `/etc/nixos/flake.nix`, you can integrate NiXOA using both flakes as inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Reference both flakes
    nixoa-vm.url = "path:/etc/nixos/nixoa/nixoa-vm";
    nixoa-config.url = "path:/etc/nixos/nixoa/user-config";
  };

  outputs = { self, nixpkgs, nixoa-vm, nixoa-config }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixoa-vm.nixosModules.default        # Imports options.nixoa.* definitions
        nixoa-config.nixosModules.default    # Sets config.nixoa.* from TOML
        nixoa-config.nixosModules.hardware   # Hardware config from user-config
        {
          # You can override TOML settings here
          config.nixoa.xo.port = 8080;
          config.nixoa.admin.sshKeys = [ "ssh-ed25519 ..." ];
        }
      ];
    };
  };
}
```
---

## Configuration

### configuration.nix Structure

Configuration is managed in your **home directory** at `~/user-config/configuration.nix` using pure Nix:

```nix
{ lib, pkgs, ... }:

{
  userSettings = {
    packages.extra = [ ];  # Additional user packages
    extras.enable = false;  # Enable terminal enhancements (zsh, oh-my-posh, etc.)
  };

  systemSettings = {
    # Basic system identification
    hostname = "nixoa";
    username = "xoa";
    stateVersion = "25.11";
    timezone = "UTC";
    sshKeys = [ "ssh-ed25519 ..." ];  # Your SSH public keys

    # Xen Orchestra configuration
    xo = {
      port = 80;
      httpsPort = 443;
      tls = {
        enable = true;
        redirectToHttps = true;
        autoGenerate = true;  # Auto-generate self-signed certs
      };
    };

    # Storage support
    storage = {
      nfs.enable = true;
      cifs.enable = true;
      vhd.enable = true;
    };

    # System packages
    packages.system.extra = [ ];

    # Optional: Automated updates configuration
    updates = { };
  };
}
```

You can also optionally customize XO server settings in `config.nixoa.toml` (optional overrides).

**See README.md and CLI-REFERENCE.md for complete configuration examples.**

### Manual Configuration

**Xen Orchestra settings:**

Edit `/etc/xo-server/config.toml` after initial deployment:

```toml
# LDAP authentication
[authentication.ldap]
uri = "ldap://ldap.example.com"
bind.dn = "cn=xo,ou=users,dc=example,dc=com"
bind.password = "secret"

# Email alerts
[mail]
from = "xo@example.com"
transport = "smtp://smtp.example.com:587"
```

Then restart:
```bash
sudo systemctl restart xo-server.service
```

**Custom SSL certificates:**

```bash
# Replace auto-generated certificates
sudo cp your-cert.pem /etc/ssl/xo/certificate.pem
sudo cp your-key.pem /etc/ssl/xo/key.pem
sudo chown xo:xo /etc/ssl/xo/*.pem
sudo chmod 640 /etc/ssl/xo/*.pem
sudo systemctl restart xo-server.service
```

---

## Automated Updates

Enable automatic updates in `~/user-config/configuration.nix`:

```nix
systemSettings = {
  updates = {
    # Garbage collection - runs independently
    gc = {
      enable = true;
      schedule = "Sun 04:00";
      keepGenerations = 7;
    };

    # Pull flake updates from remote repository
    flake = {
      enable = true;
      schedule = "Sun 04:00";
      remoteUrl = "https://codeberg.org/nixoa/nixoa-vm.git";
      branch = "main";
      autoRebuild = false;
    };

    # Update NixOS packages
    nixpkgs = {
      enable = true;
      schedule = "Mon 04:00";
      keepGenerations = 7;
    };

    # Update Xen Orchestra upstream source
    xoa = {
      enable = true;
      schedule = "Tue 04:00";
      keepGenerations = 7;
    };
  };
};
```

**How it works:**
- Each timer runs independently on its schedule
- Configuration in user-config is separate and unaffected by nixoa-vm updates
- hardware-configuration.nix lives in user-config (version controlled separately)
- Automatic GC keeps your system clean
- All updates are logged to journald

**Manual updates:**

```bash
# From your repository directory
cd /etc/nixos/nixoa/nixoa-vm  # or wherever you cloned it

# Update XO to latest release
nix run .#update-xo

# Update and rebuild immediately
sudo xoa-update-xoSrc-rebuild

# Update nixpkgs and rebuild
sudo xoa-update-nixpkgs-rebuild

# Just run garbage collection
sudo xoa-gc-generations
```

---

## Service Management

### Check Status

```bash
# All XO services at once
systemctl status xo-build xo-server redis-xo

# Individual services
sudo systemctl status xo-server.service
sudo systemctl status xo-build.service
sudo systemctl status redis-xo.service
```

### View Logs

```bash
# Follow all XO logs (recommended)
sudo journalctl -u xo-build -u xo-server -u redis-xo -f

# Individual service logs
sudo journalctl -u xo-server -n 50 -f
sudo journalctl -u xo-build -e

# Check for errors
sudo journalctl -u xo-server -p err -e
```

### Restart Services

```bash
# Restart XO server only
sudo systemctl restart xo-server.service

# Rebuild from source and restart
sudo systemctl restart xo-build.service xo-server.service

# Full system rebuild (from repository directory)
cd /etc/nixos/nixoa/nixoa-vm  # or wherever you cloned it
sudo nixos-rebuild switch --flake .#xoa -L
```

---

## Troubleshooting

### Build Fails

**Symptom:** `xo-build.service` fails during startup

```bash
# Check build logs
sudo journalctl -u xo-build -e

# Common issues:
# - Network timeout → increase TimeoutStartSec in module
# - Disk space → run: sudo nix-collect-garbage -d
# - Memory → add swap or increase RAM

# Manually trigger rebuild
sudo systemctl start xo-build.service
```

### Server Won't Start

**Symptom:** `xo-server.service` fails or crashes

```bash
# Verify build completed
ls -la /var/lib/xo/app/packages/xo-server/dist/

# Check Redis is running
sudo systemctl status redis-xo.service

# Verify config syntax
cat /etc/xo-server/config.toml

# Check permissions
ls -la /var/lib/xo/

# Test Redis connection
sudo -u xo redis-cli -s /run/redis-xo/redis.sock ping
```

### Can't Access Web Interface

**Symptom:** Connection refused or timeout

```bash
# Check if server is listening
sudo ss -tlnp | grep -E ':(80|443)'

# Verify firewall rules
sudo iptables -L -n | grep -E '(80|443)'

# Test locally
curl -k https://localhost/

# Check SSL certificates
sudo openssl x509 -in /etc/ssl/xo/certificate.pem -text -noout
```

### Mount Operations Fail

**Symptom:** Remote storage mounts fail in XO

```bash
# Test sudo privileges
sudo -u xo sudo mount

# Check FUSE module
lsmod | grep fuse

# Test vhdimount
which vhdimount
vhdimount --version

# Manual mount test (NFS)
sudo mount -t nfs server.example.com:/export /mnt/test
sudo umount /mnt/test

# Manual mount test (CIFS)
sudo mount -t cifs //server/share /mnt/test -o username=user,password=pass
sudo umount /mnt/test
```

### SSH Access Issues

**Symptom:** Can't SSH as admin user

```bash
# Verify SSH key
sudo cat /home/xoa/.ssh/authorized_keys

# Check SSH daemon
sudo systemctl status sshd

# Test SSH config
sudo sshd -T | grep -E '(PermitRoot|PasswordAuth|AllowUsers)'

# Check user exists
id xoa

# Review SSH logs
sudo journalctl -u sshd -n 50
```

### Update Timers Not Running

**Symptom:** Automatic updates aren't happening

```bash
# List all update timers
systemctl list-timers | grep xoa

# Check timer status
sudo systemctl status xoa-xo-update.timer
sudo systemctl status xoa-nixpkgs-update.timer

# View timer logs
sudo journalctl -u xoa-xo-update.service -e

# Check update status
sudo xoa-update-status

# Manually trigger update
sudo systemctl start xoa-xo-update.service
```

### Notifications Not Working

**Symptom:** Not receiving update notifications

**For ntfy.sh:**
```bash
# Test notification manually
curl -H "Title: Test" -d "Testing ntfy from XOA" \
  https://ntfy.sh/your-topic-name

# Check if curl is available
which curl

# Verify configuration in configuration.nix
cat ~/user-config/configuration.nix | grep -A5 "updates"
```

**For email:**
```bash
# Test email sending
echo "Test email" | mail -s "Test" admin@example.com

# Check mail configuration
systemctl status msmtp

# View mail logs
journalctl -u msmtp -e
```

**For webhooks:**
```bash
# Test webhook manually
curl -X POST "https://your-webhook-url" \
  -H "Content-Type: application/json" \
  -d '{"subject":"Test","body":"Testing webhook","priority":"success"}'

# Check service logs for webhook errors
sudo journalctl -u xoa-xo-update.service | grep -i webhook
```

---

## Security Notes

### Default Security Posture

- ✅ **No root login** - SSH disabled for root
- ✅ **Key-based auth only** - Password authentication disabled
- ✅ **Service isolation** - XO runs as unprivileged `xo` user
- ✅ **Minimal sudo** - Only mount/umount operations allowed
- ✅ **Private Redis** - Unix socket, not network exposed
- ✅ **Self-signed TLS** - HTTPS enabled by default

### Hardening Recommendations

1. **Use Let's Encrypt** - Replace self-signed certificates:

```nix
# Add to flake.nix or separate module
services.nginx = {
  enable = true;
  virtualHosts."xo.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:80";
  };
};
security.acme.defaults.email = "admin@example.com";
```

2. **Firewall configuration**:

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 443 ];  # SSH and HTTPS only
};
```

3. **Change default XO password immediately** after first login

4. **Enable fail2ban** for SSH protection:

```nix
services.fail2ban.enable = true;
```

---

## Performance Tuning

For large deployments (50+ VMs), add to your `nixoa.toml`:

```toml
# Note: Advanced options may require custom module configuration
# For now, edit /etc/xo-server/config.toml directly and restart xo-server

# Or create a custom NixOS module to override:
# xoa.xo.extraServerEnv = {
#   NODE_OPTIONS = "--max-old-space-size=8192";  # 8GB heap
# };
#
# services.redis.servers."xo".settings.maxmemory = "2gb";
```

---

## Module Architecture

NixOA modules are organized by concern for clarity and maintainability:

**core/** - System-level modules (no XO-specific logic)
- `base.nix` - System ID, locale, bootloader, kernel support
- `users.nix` - User accounts, groups, SSH, sudo, PAM
- `networking.nix` - Network config, firewall, NFS support
- `packages.nix` - System packages, Nix configuration, GC
- `services.nix` - Journald, monitoring, custom service definitions

**xo/** - XO-specific modules
- `integration.nix` - Bridges systemSettings → XO service configuration
- `xoa.nix` - Core XO service, build system, Node.js setup
- `xo-config.nix` - Generates `/etc/xo-server/config.nixoa.toml`
- `storage.nix` - NFS/CIFS/VHD remote storage support
- `libvhdi.nix` - VHD (Virtual Hard Disk) library service
- `autocert.nix` - Automatic TLS certificate generation
- `updates.nix` - Automated NiXOA update system
- `extras.nix` - Terminal enhancements (zsh, oh-my-posh, tools)
- `nixoa-cli.nix` - NiXOA CLI tools and utilities

**home/** - Home Manager configuration
- `home.nix` - Admin user environment, packages, shell aliases

**Dynamic bundling:**
- `bundle.nix` - Recursively discovers and imports all .nix files
- `default.nix` - Simple entry point that delegates to bundle.nix

---

## Directory Structure

```
/home/<user>/
└── user-config/                 # Configuration flake (your home directory)
    ├── flake.nix                # Simplified flake (data exports only)
    ├── configuration.nix        # Pure Nix configuration (systemSettings, userSettings)
    ├── config.nixoa.toml        # Optional XO server config overrides
    ├── hardware-configuration.nix  # Your hardware config
    └── scripts/
        ├── apply-config.sh      # Commit and rebuild
        ├── commit-config.sh     # Commit configuration changes
        ├── show-diff.sh         # Show diff from HEAD
        └── history              # Show git history

/etc/nixos/nixoa/
├── nixoa-vm/                    # Deployment flake (this repository)
│   ├── flake.nix                # Main flake definition
│   ├── README.md                # This file
│   ├── MIGRATION.md             # Migration guide for existing users
│   ├── modules/                 # Organized modular system
│   │   ├── default.nix          # Entry point (delegates to bundle.nix)
│   │   ├── bundle.nix           # Dynamic module discovery
│   │   ├── core/
│   │   │   ├── base.nix
│   │   │   ├── users.nix
│   │   │   ├── networking.nix
│   │   │   ├── packages.nix
│   │   │   └── services.nix
│   │   ├── xo/
│   │   │   ├── integration.nix
│   │   │   ├── xoa.nix
│   │   │   ├── xo-config.nix
│   │   │   ├── storage.nix
│   │   │   ├── libvhdi.nix
│   │   │   ├── autocert.nix
│   │   │   ├── updates.nix
│   │   │   ├── extras.nix
│   │   │   └── nixoa-cli.nix
│   │   └── home/
│   │       └── home.nix
│   ├── hardware-configuration.nix  # Reference template
│   └── scripts/
│       ├── xoa-install.sh       # Initial deployment
│       ├── xoa-logs.sh          # View logs
│       └── xoa-update.sh        # Manual XO update
│
└── user-config → /home/<user>/user-config  # Symlink for flake input
```

### Module Design

- **Clear separation of concerns**: Core system modules are independent of XO, making the system reusable
- **Single responsibility**: Each module handles one logical domain (users, networking, services, etc.)
- **Focused modules**: 100-150 lines each vs. monolithic 500+ line files
- **Dynamic discovery**: New modules in any subdirectory are automatically imported
- **Explicit organization**: Subdirectories (core/, xo/, home/) make the architecture clear at a glance

---

## Contributing

Contributions welcome! Please:
1. Test changes thoroughly
2. Update documentation
3. Keep `options.nixoa.*` definitions well-documented with clear types and descriptions
4. Update MIGRATION-OPTIONS.md when adding new options
5. Ensure user-config TOML converter handles new options correctly
6. Test with both TOML and pure Nix configuration methods

---

## Resources

- [Xen Orchestra Docs](https://xen-orchestra.com/docs/)
- [XCP-ng Forums](https://xcp-ng.org/forum/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Project Repository](https://codeberg.org/nixoa/nixoa-vm)

---

## License

This project is licensed under the **Apache License 2.0**.

**Copyright (c) 2023-2025 Dale Morgan**
Licensed as of: December 3, 2025

**Author and Maintainer:** Dale Morgan

See [LICENSE](./LICENSE) for the full text and [legal/NOTICE](./legal/NOTICE) for additional notices.

**Note:** This license applies to the NixOS configuration and integration code in this repository. Xen Orchestra itself remains under the AGPL-3.0 license.