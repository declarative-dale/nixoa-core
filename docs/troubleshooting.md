# Troubleshooting Guide

Solutions for common NiXOA problems.

## General Troubleshooting Steps

Before diving into specific issues:

1. **Check service status:**
   ```bash
   sudo systemctl status xo-server redis-xo
   ```

2. **View recent logs:**
   ```bash
   sudo journalctl -u xo-server -n 50
   ```

3. **Check disk space:**
   ```bash
   df -h
   ```

4. **Verify connectivity:**
   ```bash
   curl -k https://localhost/
   ```

## XO Won't Start

**Symptoms:** XO service fails or crashes immediately

### Check Prerequisites

```bash
# Verify Redis is running
sudo systemctl status redis-xo.service

# Check configuration file exists
ls -la /etc/xo-server/config.nixoa.toml

# Check permissions
ls -la /var/lib/xo/
```

### Check Logs

```bash
# See full error
sudo journalctl -u xo-server -e

# View last 100 lines
sudo journalctl -u xo-server -n 100
```

### Common Causes

**Redis not running:**
```bash
sudo systemctl restart redis-xo.service
```

**Disk full:**
```bash
df -h
```

**Memory issues:**
```bash
free -h
# If low on memory, add swap or increase VM RAM
```

**Configuration syntax error:**
```bash
cd ~/user-config
nix flake check .
```

### Recovery

```bash
# Try restarting
sudo systemctl restart xo-server.service

# If that fails, rollback to previous generation
sudo nixos-rebuild switch --rollback

# Then check logs
sudo journalctl -u xo-server -e
```

## Can't Connect to Web Interface

**Symptoms:** Connection refused, timeout, or ERR_CONNECTION_REFUSED

### Check Service is Listening

```bash
# Check if XO is listening on port 80/443
sudo ss -tlnp | grep -E ':80|:443'

# Expected output: LISTEN ports 80 and 443
```

### Test Locally

```bash
# Test connection locally
curl -k https://localhost/

# If that works but remote connection fails, check firewall
sudo iptables -L -n | grep -E ':(80|443)'
```

### Check Firewall

```bash
# View firewall rules
sudo iptables -L -n

# Allow HTTP/HTTPS
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Make permanent via configuration
# Edit ~/user-config/configuration.nix:
# systemSettings.networking.firewall.allowedTCPPorts = [ 80 443 ];
./scripts/apply-config "Opened firewall ports"
```

### Check SSL Certificate

```bash
# View certificate info
sudo openssl x509 -in /etc/ssl/xo/certificate.pem -text -noout

# Check certificate expiration
sudo openssl x509 -in /etc/ssl/xo/certificate.pem -noout -dates
```

## SSH Access Issues

**Symptoms:** Cannot SSH to the system

### Check SSH Daemon

```bash
# Check SSH service status
sudo systemctl status sshd.service

# Restart SSH
sudo systemctl restart sshd.service
```

### Verify SSH Key

```bash
# Check authorized keys
sudo cat /home/xoa/.ssh/authorized_keys

# Should match what you configured
# Check ~/user-config/configuration.nix
```

### Test SSH

```bash
# Verbose output to see what's happening
ssh -v xoa@YOUR-IP

# Try from different machine
ssh -i ~/.ssh/your-key xoa@YOUR-IP
```

### Fix SSH Issues

```bash
# Add your SSH key
# Edit ~/user-config/configuration.nix:
# systemSettings.sshKeys = [ "your-key-here" ];

./scripts/apply-config "Added SSH key"

# Then test
ssh xoa@YOUR-IP
```

## Rebuild Failed

**Symptoms:** `nixos-rebuild` fails with errors

### Check Configuration

```bash
cd ~/user-config

# Validate Nix syntax
nix flake check .

# Specific file check
nix eval -f configuration.nix
```

### Common Errors

**Syntax error:**
```
Expected ... but got ...
```
Check your Nix file for missing brackets, semicolons, or quotes.

**Package not found:**
```
error: attribute 'packagename' missing
```
Package name is wrong. Search for correct name:
```bash
nix search nixpkgs packagename
```

**Out of disk space:**
```bash
df -h
```

**Network timeout:**
```bash
# Rebuild with verbose output
sudo nixos-rebuild switch --flake .#HOSTNAME -L

# Check internet connection
ping 8.8.8.8

# Try again
sudo nixos-rebuild switch --flake .#HOSTNAME
```

### Rebuild from Scratch

```bash
# Full rebuild with cache cleared
sudo nixos-rebuild switch --flake .#HOSTNAME --recreate-lock-file

# Or if that fails, rollback
sudo nixos-rebuild switch --rollback
```

## Storage Mount Failures

**Symptoms:** Can't mount NFS/CIFS storage in XO

### Check Storage Support

```bash
# Verify NFS support
sudo mount -t nfs -V

# Verify CIFS support
sudo mount -t cifs -V
```

### Test Manual Mount

```bash
# Test NFS
sudo mount -t nfs server.example.com:/export /mnt/test

# Test CIFS
sudo mount -t cifs //server/share /mnt/test -o username=user,password=pass

# Check if mounted
mount | grep /mnt/test

# Unmount when done
sudo umount /mnt/test
```

### Check XO Mount Directory

```bash
# Should exist and be writable
sudo ls -la /var/lib/xo/mounts/

# Set correct permissions
sudo chown xo:xo /var/lib/xo/mounts/
```

### Enable Storage in Configuration

```nix
systemSettings.storage = {
  nfs.enable = true;
  cifs.enable = true;
};
```

Then apply:
```bash
./scripts/apply-config "Enabled storage"
```

## High Disk Usage

**Symptoms:** Disk full or running out of space

### Identify What's Using Space

```bash
# Check overall usage
df -h

# Check directories
du -sh /* | sort -h

# Check Nix store
du -sh /nix/store

# Check XO data
du -sh /var/lib/xo/
```

### Nix Store Cleanup

Garbage collection and store optimization are automatically handled by Determinate Nix.

### Clean XO Data

```bash
# Check what's using space
sudo du -sh /var/lib/xo/*

# Clear logs if very large
sudo journalctl --vacuum=10d
```

## High Memory Usage

**Symptoms:** System slow, OOM (Out of Memory) errors

### Check Memory

```bash
# Overall memory usage
free -h

# Per-process memory
top
ps aux --sort=-%mem | head -20
```

### Check XO Memory

```bash
# XO process memory
ps aux | grep xo-server

# Check if Node.js is using too much
ps aux | grep node
```

### Increase XO Memory Limit

In `~/user-config/configuration.nix`:

```nix
# This requires adding custom module configuration
# Temporary solution: increase system RAM
```

### Memory Pressure

```bash
# Check swap usage
free -h

# If swap full, add more or restart services
sudo systemctl restart xo-server.service
```

## Logs Are Full

**Symptoms:** Disk full because of log files

### Check Log Size

```bash
journalctl --disk-usage
```

### Vacuum Logs

```bash
# Keep last 10 days
sudo journalctl --vacuum=10d

# Keep last 100 MB
sudo journalctl --vacuum-size=100M

# Aggressive cleanup
sudo journalctl --vacuum-time=7d
```

## Updates Failed

**Symptoms:** Update timers aren't running or update failed

### Check Update Timers

```bash
# List all timers
systemctl list-timers

# Check specific timer
sudo systemctl status xoa-nixpkgs-update.timer
```

### Manually Trigger Update

```bash
# Check status of an update service
sudo systemctl status xoa-nixpkgs-update.service

# View logs
sudo journalctl -u xoa-nixpkgs-update.service -e
```

### Check Update Configuration

Verify in `~/user-config/configuration.nix` that your desired updates are enabled (autoUpgrade, nixpkgs, xoa, etc.).

## Rollback to Previous Version

If something breaks after an update:

```bash
# See available generations
sudo nixos-rebuild list-generations

# Example output:
#   257  2025-12-29 10:30:45 (current)
#   256  2025-12-28 15:22:10

# Rollback to previous
sudo nixos-rebuild switch --rollback

# Or switch to specific generation
sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system -p 256
```

## Getting More Help

### View Detailed Logs

```bash
# Get full system logs
sudo journalctl -b

# XO-specific logs
sudo journalctl -u xo-server -u redis-xo -x

# Since last reboot with priority
sudo journalctl -b -p err
```

### Debug Mode

```bash
# Rebuild with verbose output
sudo nixos-rebuild switch --flake .#HOSTNAME -L

# Show what will change (dry-run)
sudo nixos-rebuild dry-run --flake .#HOSTNAME
```

### Ask for Help

When reporting issues, include:

```bash
# System info
uname -a
nixos-version

# Configuration (sanitized)
cat ~/user-config/configuration.nix

# Recent logs
sudo journalctl -u xo-server -n 50

# Resource usage
free -h
df -h
```

Then visit: [Issues](https://codeberg.org/nixoa/nixoa-vm/issues)

## See Also

- [Operations Guide](./operations.md) - Daily operations
- [Configuration Guide](./configuration.md) - Configuration reference
- [Getting Started](./getting-started.md) - Quick start
