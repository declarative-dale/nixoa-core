# Daily Operations

How to manage and operate your NiXOA system day-to-day.

## Service Management

### Check Service Status

```bash
# Check XO server
sudo systemctl status xo-server.service

# Check Redis
sudo systemctl status redis-xo.service

# Check all XO services
systemctl status xo-server redis-xo
```

### Restart Services

```bash
# Restart XO only
sudo systemctl restart xo-server.service

# Restart Redis
sudo systemctl restart redis-xo.service

# Restart all XO services
sudo systemctl restart xo-server redis-xo
```

### Stop/Start Services

```bash
# Stop XO
sudo systemctl stop xo-server.service

# Start XO
sudo systemctl start xo-server.service

# Disable on boot (stops autostart)
sudo systemctl disable xo-server.service

# Enable on boot
sudo systemctl enable xo-server.service
```

## Viewing Logs

### Real-Time Logs

```bash
# Follow XO logs
sudo journalctl -u xo-server -f

# Follow all XO services
sudo journalctl -u xo-server -u redis-xo -f

# Follow with timestamps
sudo journalctl -u xo-server -f --no-pager
```

### Recent Logs

```bash
# Last 50 lines
sudo journalctl -u xo-server -n 50

# Last 100 lines
sudo journalctl -u xo-server -n 100

# Just the end
sudo journalctl -u xo-server -e
```

### Filtered Logs

```bash
# Show errors only
sudo journalctl -u xo-server -p err

# Show warnings and above
sudo journalctl -u xo-server -p warning

# Show since last boot
sudo journalctl -u xo-server -b

# Show since 2 hours ago
sudo journalctl -u xo-server --since "2 hours ago"
```

## System Status

### Check Disk Space

```bash
df -h                 # Overall filesystem usage
du -sh /var/lib/xo    # XO data directory size
du -sh /nix/store     # Nix store size
```

### Check Memory Usage

```bash
free -h
top
```

### Check Network

```bash
# View listening ports
sudo ss -tlnp | grep -E ':80|:443|:6379'

# View connections
sudo ss -tun

# Test XO connectivity
curl -k https://localhost/
```

## Configuration Changes

### Make Changes

```bash
cd ~/user-config
nano configuration.nix
```

### Review Changes

```bash
cd ~/user-config
./scripts/show-diff
```

### Apply Changes

```bash
cd ~/user-config
./scripts/apply-config "Description of changes"
```

### View Commit History

```bash
cd ~/user-config
./scripts/history

# Or use git directly
git log --oneline
git show <commit-hash>
```

## System Updates

### Automated Updates

Updates run on schedules if enabled in configuration:

```bash
# Check if update timers are running
systemctl list-timers | grep xoa

# View update status
sudo systemctl status xoa-nixpkgs-update.timer
sudo systemctl status xoa-xoa-update.timer
```

### Trigger Automatic Update Manually

```bash
# Update NixPkgs
sudo systemctl start xoa-nixpkgs-update.service

# Update XOA
sudo systemctl start xoa-xoa-update.service
```

### Manual System Rebuild

```bash
cd ~/user-config
sudo nixos-rebuild switch --flake .#HOSTNAME -L
```

## Rollback to Previous Generation

If something breaks after an update:

```bash
# See available generations
sudo nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or switch to a specific generation
sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --rollback
```

## System Information

### Check Version

```bash
# NixOS version
nixos-version

# XO version
curl -s https://localhost/api/version 2>/dev/null | jq .

# Or check service
systemctl status xo-server | grep Active
```

### Check Hostname and Users

```bash
hostname
whoami
id
```

### Check NixOS Configuration

```bash
# Show current system config
nix eval --raw nixpkgs#stdenv.system

# Show flake version
git -C /etc/nixos/nixoa-vm show-ref
```

## Accessing Xen Orchestra

### Web Interface

```
HTTPS: https://YOUR-IP/
HTTP:  http://YOUR-IP/ (redirects to HTTPS)
v6 UI: https://YOUR-IP/v6
```

### SSH Access

```bash
# SSH as admin user
ssh xoa@YOUR-IP

# SSH as root (if enabled)
ssh root@YOUR-IP
```

### Local Console Commands

```bash
# Restart XO service
sudo systemctl restart xo-server.service

# Check XO is listening
sudo ss -tlnp | grep 80
sudo ss -tlnp | grep 443

# Test local connection
curl -k https://localhost/
```

## Monitoring

### Resources in Use

```bash
# Real-time resource monitoring
top

# Better alternative (if installed)
bottom

# XO process only
ps aux | grep xo-server
```

### Redis Status

```bash
# Check Redis socket exists
ls -la /run/redis-xo/redis.sock

# Test Redis
sudo -u xo redis-cli -s /run/redis-xo/redis.sock ping
```

## Maintenance Tasks

### Nix Store

Garbage collection and store optimization are automatically handled by Determinate Nix.

### Check Filesystem

```bash
# Check filesystem errors
sudo fsck -n /  # -n = don't fix, just check

# Check disk usage by directory
du -sh /*
```

### Review System Logs

```bash
# All system logs
sudo journalctl --all

# Show system startup logs
sudo journalctl -b

# Show full logs
sudo journalctl | tail -200
```

## Troubleshooting Commands

See [Troubleshooting](./troubleshooting.md) for common issues and solutions.

Quick diagnostic:

```bash
# Check key services
systemctl status xo-server redis-xo

# View recent errors
journalctl -p err -n 50

# Check disk space
df -h

# Check network
ip addr
```
