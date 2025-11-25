# Xen Orchestra on NixOS

A complete, production-ready Xen Orchestra Community Edition deployment for NixOS with automated updates and secure defaults.

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

### 1. Clone Repository

Choose a persistent location that survives system rebuilds:

```bash
# Option A: System-wide (recommended)
sudo mkdir -p /etc/nixos
cd /etc/nixos
sudo git clone https://codeberg.org/dalemorgan/declarative-xoa-ce.git
cd declarative-xoa-ce

# Option B: User home directory
cd ~
git clone https://codeberg.org/dalemorgan/declarative-xoa-ce.git
cd declarative-xoa-ce
```

### 2. Configure System

Create your configuration file from the sample:

```bash
cp sample-nixoa.toml nixoa.toml
nano nixoa.toml
```

**Required changes:**
- `hostname` - Your system's hostname
- `username` - Admin user for SSH access
- `sshKeys` - Your SSH public key(s)

**Optional changes:**
- `xo.port` / `xo.httpsPort` - Change default ports
- `storage.*` - Enable/disable NFS and CIFS support
- `updates.repoDir` - Must match your clone location

**Copy hardware configuration:**

```bash
sudo cp /etc/nixos/hardware-configuration.nix ./
```

### 3. Deploy

```bash
# If repo is in /etc/nixos/declarative-xoa-ce
sudo nixos-rebuild switch --flake .#xoa -L

# If repo is elsewhere, use absolute path
sudo nixos-rebuild switch --flake /path/to/declarative-xoa-ce#xoa -L
```

### 4. Access Xen Orchestra

```
HTTPS: https://your-server-ip/
HTTP:  http://your-server-ip/

Default credentials (change immediately):
  Username: admin@admin.net
  Password: admin
```

---

## Configuration

### nixoa.toml Structure

This flake uses TOML for configuration, which is more human-readable and supports native comments:

```toml
# System basics
hostname = "xoa"
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
repoDir = "/etc/nixos/declarative-xoa-ce"
```

**See CONFIGURATION.md for complete documentation** on all available options.

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

Enable automatic updates in `vars.nix`:

```nix
updates = {
  repoDir = "/etc/nixos/declarative-xoa-ce";  # Your clone location
  
  # Garbage collection - runs independently
  gc = {
    enable = true;              # Keep only recent generations
    schedule = "Sun 04:00";     # When to run
    keepGenerations = 7;        # How many to keep
  };
  
  # Pull flake updates from Codeberg
  flake = {
    enable = true;              # Pull latest flake updates
    schedule = "Sun 04:00";     # When to check
    autoRebuild = false;        # Rebuild after pulling?
    protectPaths = [ "vars.nix" "hardware-configuration.nix" ];
  };
  
  # Update NixOS packages
  nixos = {
    enable = true;              # Update nixpkgs input
    schedule = "Mon 04:00";     # When to update
    keepGenerations = 7;        # GC after update
  };
  
  # Update Xen Orchestra upstream
  xoa = {
    enable = true;              # Update XO source
    schedule = "Tue 04:00";     # When to update
    keepGenerations = 7;        # GC after update
  };
};
```

**How it works:**
- Each timer runs independently on its schedule
- Updates preserve your `vars.nix` and `hardware-configuration.nix`
- Automatic GC keeps your system clean
- All updates are logged to journald

**Manual updates:**

```bash
# Update XO to latest release
nix run .#update-xo

# Update and rebuild immediately
cd /etc/nixos/declarative-xoa-ce
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

# Full system rebuild
cd /etc/nixos/declarative-xoa-ce
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
grep -A5 "ntfy" /etc/nixos/declarative-xoa-ce/vars.nix
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

For large deployments (50+ VMs):

```nix
# In vars.nix or as module options
xoa.xo.extraServerEnv = {
  NODE_OPTIONS = "--max-old-space-size=8192";  # 8GB heap
};

# Increase Redis memory
services.redis.servers."xo".settings.maxmemory = "2gb";
```

---

## Directory Structure

```
declarative-xoa-ce/
├── flake.nix                    # Main flake definition
├── vars.nix                     # User configuration
├── hardware-configuration.nix   # System hardware config
├── modules/
│   ├── xoa.nix                  # Core XO module
│   ├── storage.nix              # NFS/CIFS support
│   ├── libvhdi.nix              # VHD tools
│   └── updates.nix              # Update automation
└── scripts/
    ├── xoa-install.sh           # Initial deployment
    ├── xoa-logs.sh              # View logs
    ├── xoa-set-vars.sh          # Interactive setup
    └── xoa-update.sh            # Manual XO update
```

---

## Contributing

Contributions welcome! Please:
1. Test changes thoroughly
2. Update documentation
3. Keep `vars.nix` user-friendly
4. Maintain backward compatibility

---

## Resources

- [Xen Orchestra Docs](https://xen-orchestra.com/docs/)
- [XCP-ng Forums](https://xcp-ng.org/forum/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Project Repository](https://codeberg.org/dalemorgan/declarative-xoa-ce)

---

## License

Configuration: Public Domain / Unlicense  
Xen Orchestra: AGPL-3.0