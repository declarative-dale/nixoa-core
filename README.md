<!-- SPDX-License-Identifier: Apache-2.0 -->
# NixOA-CE: Xen Orchestra Community Edition on NixOS

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](./LICENSE)

An experimental Xen Orchestra Community Edition deployment for NixOS, ideal for homelab and testing environments.

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

> **Important:** NiXOA CE uses a **separate configuration flake** (`nixoa-ce-config`) to keep your settings isolated from the deployment code. Configuration is **NOT** stored in this repository.

> **Existing Users:** If you're upgrading from an older version with the repository named `nixoa` or `declarative-xoa-ce`, see [MIGRATION.md](./MIGRATION.md) for renaming instructions.

### 1. Clone Repositories

You need **both** the deployment flake (nixoa-ce) and configuration flake (nixoa-ce-config):

```bash
# System-wide installation (recommended)
sudo mkdir -p /etc/nixos
cd /etc/nixos

# Clone deployment flake
sudo git clone https://codeberg.org/dalemorgan/nixoa-ce.git nixoa-ce

# Clone configuration flake (separate repository)
sudo git clone https://codeberg.org/dalemorgan/nixoa-ce-config.git nixoa-ce-config
```

### 2. Configure System

Edit your configuration in the **separate config repository**:

```bash
cd /etc/nixos/nixoa-ce-config
nano system-settings.toml
```

**Required changes:**
- `hostname` - Your system's hostname
- `username` - Admin user for SSH access
- `sshKeys` - Your SSH public key(s)

**Optional changes:**
- `xo.port` / `xo.httpsPort` - Change default ports
- `storage.*` - Enable/disable NFS and CIFS support
- `updates.repoDir` - Path to nixoa-ce repository (default: `/etc/nixos/nixoa-ce`)
- `extras.enable` - Enhanced terminal experience with zsh
- `services.*` - Custom NixOS services

**Commit your configuration** (recommended for version control):
```bash
./scripts/commit-config.sh "Initial configuration"
```

**Copy hardware configuration to nixoa-ce-config:**

```bash
# Hardware config must be in nixoa-ce-config (not nixoa-ce)
sudo cp /etc/nixos/hardware-configuration.nix /etc/nixos/nixoa-ce-config/
cd /etc/nixos/nixoa-ce-config
./commit-config "Add hardware-configuration.nix"
```

### 3. Deploy

```bash
cd /etc/nixos/nixoa-ce
sudo nixos-rebuild switch --flake .#nixoa -L
```

The flake will automatically:
1. Read configuration from `nixoa-ce-config/system-settings.toml`
2. Apply settings via the `options.nixoa.*` module system
3. Build and activate your NiXOA system

**Note:** The configuration name is always `nixoa` (not based on your hostname).

**✅ Correct references** (path-based):
```bash
sudo nixos-rebuild switch --flake .#nixoa                      # ✅ Current directory
sudo nixos-rebuild switch --flake /etc/nixos/nixoa-ce#nixoa    # ✅ Absolute path
sudo nixos-rebuild switch --flake ~/nixoa-ce#nixoa             # ✅ Home directory
```

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
    nixoa-ce.url = "path:/etc/nixos/nixoa-ce";
    nixoa-config.url = "path:/etc/nixos/nixoa-ce-config";
  };

  outputs = { self, nixpkgs, nixoa-ce, nixoa-config }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixoa-ce.nixosModules.default        # Imports options.nixoa.* definitions
        nixoa-config.nixosModules.default    # Sets config.nixoa.* from TOML
        nixoa-config.nixosModules.hardware   # Hardware config from nixoa-ce-config
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

**Alternative: Pure Nix Configuration**

Skip nixoa-ce-config and configure directly in Nix:

```nix
{
  inputs.nixoa-ce.url = "path:/etc/nixos/nixoa-ce";

  outputs = { nixpkgs, nixoa-ce, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixoa-ce.nixosModules.default
        ./hardware-configuration.nix
        {
          config.nixoa = {
            hostname = "myhost";
            admin = {
              username = "admin";
              sshKeys = [ "ssh-ed25519 ..." ];
            };
            xo.port = 8080;
            # ... all other options
          };
        }
      ];
    };
  };
}
```

**See MIGRATION-OPTIONS.md** for complete options reference.

---

## Configuration

### system-settings.toml Structure

Configuration is managed in the **separate nixoa-ce-config repository** at `/etc/nixos/nixoa-ce-config/system-settings.toml`:

```toml
# System basics
hostname = "nixoa"
username = "xoa"
sshKeys = ["ssh-ed25519 ..."]  # Your public keys

# Xen Orchestra ports
[xo]
port = 80
httpsPort = 443

# TLS settings
[tls]
enable = true  # Auto-generate self-signed certs

# Storage support
[storage.nfs]
enable = true  # Enable NFS mounting

[storage.cifs]
enable = true  # Enable CIFS/SMB mounting

# Updates - see "Automated Updates" section
[updates]
repoDir = "/etc/nixos/nixoa-ce"  # Must match where you cloned the repository
```

**See MIGRATION-OPTIONS.md for complete options documentation** including pure Nix configuration methods.

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

Enable automatic updates in `/etc/nixos/nixoa-ce-config/system-settings.toml`:

```toml
[updates]
repoDir = "/etc/nixos/nixoa-ce"  # Your clone location (must match where you cloned)

# Garbage collection - runs independently
[updates.gc]
enable = true
schedule = "Sun 04:00"
keepGenerations = 7

# Pull flake updates from remote repository
[updates.flake]
enable = true
schedule = "Sun 04:00"
remoteUrl = "https://codeberg.org/dalemorgan/nixoa-ce.git"
branch = "main"
autoRebuild = false

# Update NixOS packages
[updates.nixpkgs]
enable = true
schedule = "Mon 04:00"
keepGenerations = 7

# Update Xen Orchestra upstream source
[updates.xoa]
enable = true
schedule = "Tue 04:00"
keepGenerations = 7
```

**How it works:**
- Each timer runs independently on its schedule
- Configuration in nixoa-ce-config is separate and unaffected by nixoa-ce updates
- hardware-configuration.nix lives in nixoa-ce-config (version controlled separately)
- Automatic GC keeps your system clean
- All updates are logged to journald

**Manual updates:**

```bash
# From your repository directory
cd /etc/nixos/nixoa-ce  # or wherever you cloned it

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
cd /etc/nixos/nixoa-ce  # or wherever you cloned it
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

# Verify configuration
grep -A5 "ntfy" /etc/nixos/nixoa-ce-config/system-settings.toml
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

## Directory Structure

```
/etc/nixos/
├── nixoa-ce/                    # Deployment flake (this repository)
│   ├── flake.nix                # Main flake definition
│   ├── MIGRATION-OPTIONS.md     # Options architecture documentation
│   ├── modules/
│   │   ├── nixoa-options.nix    # options.nixoa.* definitions
│   │   ├── xoa.nix              # Core XO module
│   │   ├── system.nix           # System configuration
│   │   ├── storage.nix          # NFS/CIFS support
│   │   ├── libvhdi.nix          # VHD tools
│   │   ├── autocert.nix         # Auto SSL certificate generation
│   │   └── updates.nix          # Update automation
│   └── scripts/
│       ├── xoa-install.sh       # Initial deployment
│       ├── xoa-logs.sh          # View logs
│       └── xoa-update.sh        # Manual XO update
│
└── nixoa-ce-config/             # Configuration flake (separate repository)
    ├── flake.nix                # Exports NixOS module
    ├── system-settings.toml     # Your configuration (TOML frontend)
    ├── modules/
    │   └── nixoa-config.nix     # TOML → NixOS module converter
    └── scripts/
        └── commit-config.sh     # Commit configuration changes
```

---

## Contributing

Contributions welcome! Please:
1. Test changes thoroughly
2. Update documentation
3. Keep `options.nixoa.*` definitions well-documented with clear types and descriptions
4. Update MIGRATION-OPTIONS.md when adding new options
5. Ensure nixoa-ce-config TOML converter handles new options correctly
6. Test with both TOML and pure Nix configuration methods

---

## Resources

- [Xen Orchestra Docs](https://xen-orchestra.com/docs/)
- [XCP-ng Forums](https://xcp-ng.org/forum/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Project Repository](https://codeberg.org/dalemorgan/nixoa-ce)

---

## License

This project is licensed under the **Apache License 2.0**.

**Copyright (c) 2023-2025 Dale Morgan**
Licensed as of: December 3, 2025

**Author and Maintainer:** Dale Morgan

See [LICENSE](./LICENSE) for the full text and [legal/NOTICE](./legal/NOTICE) for additional notices.

**Note:** This license applies to the NixOS configuration and integration code in this repository. Xen Orchestra itself remains under the AGPL-3.0 license.