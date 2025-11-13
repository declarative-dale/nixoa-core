# Xen Orchestra on NixOS - Full Installation Guide

This flake provides a proof of concept implementation of Xen Orchestra Community Edition on NixOS with features such as:

- ✅ Build from pinned source (GitHub)
- ✅ HTTPS with self-signed certificates (auto-generated)
- ✅ Rootless operation with `xo` service account
- ✅ SMB/CIFS remote mounting with sudo
- ✅ NFS remote mounting with sudo
- ✅ VHD/VHDX operations via libvhdi (vhdimount, vhdiinfo)
- ✅ Dedicated Redis instance (Unix socket)
- ✅ Secure SSH-only admin access
- ✅ Automatic builds and updates

## Directory Structure

```
.
├── flake.nix
├── vars.nix
├── hardware-configuration.nix
├── modules/
└── scripts/
```

## Quick Start

### 1. Prerequisites

- NixOS 25.05 or newer
- Flakes enabled in your Nix configuration
- SSH access to your target system
- Your SSH public key ready

### 2. Initial Setup
```bash
sudo nixos-rebuild switch --flake 'git+https://codeberg.org/dalemorgan/declarative-xoa-ce#xoa'
```
```bash
git clone https://codeberg.org/dalemorgan/declarative-xoa-ce
cd declarative-xoa-ce

# Create vars.nix and copy hardware-configuration.nix from the system
./scripts/xoa-set-vars.sh
# If you didn’t run the script or want to copy manually:
#   mkdir -p hosts/<HOST>
#   sudo cp /etc/nixos/hardware-configuration.nix ./hardware-configuration.nix

```

### 3. Deploy

```bash
./scripts/xoa-install.sh
# or explicitly:
# sudo nixos-rebuild switch --flake .#<HOST> -L --show-trace
```

### 4. Access XO

```
HTTPS: https://your-server-ip/
HTTP:  http://your-server-ip/

Default credentials on first login:
Username: admin@admin.net
Password: admin

⚠️ CHANGE THE DEFAULT PASSWORD IMMEDIATELY!
```

## Configuration Overview

### XO Service Configuration

Located in `modules/system.nix`:

```nix
xoa.xo = {
  enable = true;
  host = "0.0.0.0";           # Bind address
  port = 80;                  # HTTP port
  httpsPort = 443;            # HTTPS port
  
  ssl.enable = true;          # Enable HTTPS
  ssl.dir = "/etc/ssl/xo";
  ssl.key = "/etc/ssl/xo/key.pem";
  ssl.cert = "/etc/ssl/xo/certificate.pem";
  
  dataDir = "/var/lib/xo/data";      # Backup metadata
  tempDir = "/var/lib/xo/tmp";       # Temporary files
  mountsDir = "/var/lib/xo/mounts";  # Remote mounts & VHD mounts
};
```

### User Accounts

Two accounts are created:

1. **`xo`** - Service account (rootless)
   - Runs xo-server, xo-build services
   - Has sudo rights for: mount, umount, vhdimount, mount.nfs, mount.cifs
   - No shell access

2. **`xoa`** - Admin account (SSH-only)
   - Full sudo access for system administration
   - SSH key authentication only (no password)
   - Member of wheel and systemd-journal groups

### Sudo Configuration for SR Mounting

The `xo` user has passwordless sudo for these operations:

```bash
# NFS mounts
sudo mount -t nfs server:/path /mnt/point
sudo mount.nfs server:/path /mnt/point
sudo mount.nfs4 server:/path /mnt/point

# CIFS/SMB mounts
sudo mount -t cifs //server/share /mnt/point -o credentials=/path/to/creds
sudo mount.cifs //server/share /mnt/point -o credentials=/path/to/creds

# VHD operations
sudo vhdimount /path/to/file.vhd /mnt/point
sudo vhdiinfo /path/to/file.vhd

# Generic mount/umount
sudo mount <options>
sudo umount /mnt/point
```

## Remote SR Configuration

### NFS Remotes

In XO web interface:

1. Go to **Settings** → **Remotes** → **New**
2. Select **NFS**
3. Configure:
   ```
   Host: nfs-server.example.com
   Path: /exports/xo-backups
   ```

### SMB/CIFS Remotes

1. Go to **Settings** → **Remotes** → **New**
2. Select **SMB**
3. Configure:
   ```
   Host: smb-server.example.com
   Share: backups
   Domain: WORKGROUP (or your domain)
   Username: backup-user
   Password: ********
   ```

The XO service will automatically use sudo to mount these shares.

## VHD Operations

The libvhdi tools are available system-wide:

```bash
# View VHD file information
sudo vhdiinfo /path/to/disk.vhd

# Mount VHD as a filesystem
sudo vhdimount /path/to/disk.vhd /mnt/vhd

# Access files
ls /mnt/vhd/vhdi1

# Unmount
sudo umount /mnt/vhd
```

XO uses these tools internally for backup restore operations.

## SSL Certificates

### Self-Signed (Default)

On first boot, self-signed certificates are auto-generated:
- Valid for 825 days
- CN matches the configured hostname
- Located in `/etc/ssl/xo/`

### Using Your Own Certificates

Replace the auto-generated certificates:

```bash
# Copy your certificates
sudo cp your-key.pem /etc/ssl/xo/key.pem
sudo cp your-cert.pem /etc/ssl/xo/certificate.pem

# Set permissions
sudo chown xo:xo /etc/ssl/xo/*.pem
sudo chmod 600 /etc/ssl/xo/key.pem
sudo chmod 644 /etc/ssl/xo/certificate.pem

# Restart XO
sudo systemctl restart xo-server.service
```

### Let's Encrypt (Recommended for Production)

For automatic certificate management, consider setting up a reverse proxy:

```nix
# In system.nix, add:
services.nginx = {
  enable = true;
  recommendedProxySettings = true;
  recommendedTlsSettings = true;
  
  virtualHosts."xo.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:80";
      proxyWebsockets = true;
    };
  };
};

security.acme = {
  acceptTerms = true;
  defaults.email = "admin@example.com";
};
```

## Services Management

### View Service Status

```bash
# XO build service (runs once at boot)
sudo systemctl status xo-build.service

# XO server (main service)
sudo systemctl status xo-server.service

# Redis for XO
sudo systemctl status redis-xo.service

# SSL bootstrap (runs once)
sudo systemctl status xo-bootstrap.service
```

### Restart Services

```bash
# Restart XO server only
sudo systemctl restart xo-server.service

# Rebuild XO from source and restart
sudo systemctl restart xo-build.service xo-server.service
```

### View Logs

```bash
# Follow XO build + runtime logs
./scripts/xoa-logs.sh

# Or use systemd directly:
journalctl -u xo-build -e -f
journalctl -u xo-server -e -f
journalctl -u redis-xo -e -f
systemctl status xo-server
```

## Updating Xen Orchestra

### Update to Latest Release

Use the flake app (or alias) to check/update the xen-orchestra upstream:

```bash
# from repo root
nix run .#update-xo
# or, if you prefer an alias:
alias xoa-update="nix run .#update-xo"
xoa-update
```
### What it does:

- Reads the current xoSrc rev from flake.lock,

- Runs nix flake lock --update-input xoSrc --commit-lock-file,

- Prints old → new rev,

- Tries to show commit messages between those two revisions,

- Leaves flake.lock committed so the update is recorded.

### Build logs during rebuild

- Use -L / --print-build-logs with nixos-rebuild or nix build to see derivation logs.

- For service logs after switch: journalctl -u xo-build -u xo-server -e -f.
### Manual Update (Latest Master)

```bash
cd /etc/nixos
nix flake lock --update-input xoSrc
sudo nixos-rebuild switch --flake .#xoa
```

## Troubleshooting

### Build Fails

```bash
# Follow XO build + runtime logs
./scripts/xoa-logs.sh

# Or use systemd directly:
journalctl -u xo-build -e -f
journalctl -u xo-server -e -f
journalctl -u redis-xo -e -f
systemctl status xo-server
```

### Server Won't Start

```bash
# Check if build completed
ls -la /var/lib/xo/app/packages/xo-server/dist/cli.mjs

# Check Redis
sudo systemctl status redis-xo.service

# Check config
cat /etc/xo-server/config.toml

# Check permissions
ls -la /var/lib/xo/
```

### Mount Operations Fail

```bash
# Test sudo privileges
sudo -u xo sudo mount

# Check if FUSE is available
lsmod | grep fuse

# Check vhdimount
which vhdimount
vhdimount --version

# Test NFS mount manually
sudo mount -t nfs server:/path /tmp/test

# Test CIFS mount manually
sudo mount -t cifs //server/share /tmp/test -o username=user
```

### Cannot SSH as xoa

```bash
# Check if key is added
sudo cat /home/xoa/.ssh/authorized_keys

# Check SSH service
sudo systemctl status sshd

# Check SSH config
sudo cat /etc/ssh/sshd_config | grep -E "(PermitRoot|PasswordAuth|AllowUsers)"
```

## Security Considerations

### Production Hardening

1. **Replace Self-Signed Certificates**
   - Use Let's Encrypt or your own CA-signed certificates
   - Configure a reverse proxy for better TLS management

2. **Firewall Configuration**
   - Restrict port 80/443 to trusted networks
   - Consider VPN access for XO interface
   - The default config opens: 80, 443, 3389, 5900, 8012

3. **SSH Hardening**
   - Keep SSH key-only authentication (already configured)
   - Consider changing SSH port from 22
   - Use fail2ban or similar for brute-force protection

4. **User Management**
   - Change XO admin password immediately
   - Remove default admin@admin.net account after creating your own
   - Use strong passwords for remote share credentials

5. **Backup Security**
   - Use encrypted remote shares when possible
   - Protect credentials files with appropriate permissions
   - Regular security audits of backup access logs

### Data Protection

- XO metadata: `/var/lib/xo/data`
- Temporary files: `/var/lib/xo/tmp`
- Mount points: `/var/lib/xo/mounts`
- Config: `/etc/xo-server/config.toml`

Ensure these are included in your system backups.

## Advanced Configuration

### Custom XO Server Configuration

Edit `/etc/xo-server/config.toml` directly:

```toml
# Add custom authentication providers
[authentication.ldap]
uri = "ldap://ldap.example.com"
bind.dn = "cn=xo,ou=users,dc=example,dc=com"
bind.password = "secret"

# Configure email alerts
[mail]
from = "xo@example.com"
transport = "smtp://smtp.example.com:587"
```

Then restart:
```bash
sudo systemctl restart xo-server.service
```

### Adding Extra Environment Variables

In `modules/system.nix`:

```nix
xoa.xo.extraServerEnv = {
  DEBUG = "xo:*";  # Enable debug logging
  NODE_OPTIONS = "--max-old-space-size=4096";  # Increase memory
};
```

### Disable HTTPS

In `modules/system.nix`:

```nix
xoa.xo.ssl.enable = false;
```

### Change Ports

```nix
xoa.xo.port = 8080;
xoa.xo.httpsPort = 8443;
```

Don't forget to update firewall rules in `networking.firewall.allowedTCPPorts`.

## Performance Tuning

### For Large Deployments

```nix
# Increase Node.js memory
xoa.xo.extraServerEnv.NODE_OPTIONS = "--max-old-space-size=8192";

# Increase Redis memory
services.redis.servers."xo".settings.maxmemory = "2gb";

# Use faster temp directory (if you have SSD)
xoa.xo.tempDir = "/var/tmp/xo";
```

## Contributing

To contribute improvements to this configuration:

1. Test changes thoroughly
2. Document new options
3. Update this README
4. Submit pull requests with clear descriptions

## License

This configuration is provided as-is. Xen Orchestra itself is licensed under AGPL-3.0.

## More Info

- Xen Orchestra Documentation: https://xen-orchestra.com/docs/
- XO Community Forum: https://xcp-ng.org/forum/
- NixOS Manual: https://nixos.org/manual/nixos/stable/

## Changelog

### 2025-11 - Initial Release
- Full from-source build
- SSL support with auto-generated certificates
- NFS/CIFS/VHD mounting capabilities
- Redis integration
- Security hardening
- Comprehensive documentation
