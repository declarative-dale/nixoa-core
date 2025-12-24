<!-- SPDX-License-Identifier: Apache-2.0 -->
# NiXOA Troubleshooting Quick Reference

This is a quick reference for common troubleshooting and monitoring tasks on NiXOA.

## Check Status

```bash
# Overview of all updates
sudo xoa-update-status

# List scheduled timers
systemctl list-timers 'xoa-*'

# Check specific service
sudo systemctl status xoa-xo-update.timer
sudo systemctl status xoa-xo-update.service

# View recent logs
sudo journalctl -u xoa-xo-update.service -n 50
sudo journalctl -u xoa-xo-update.service --since today
```

## Manual Operations

```bash
# Trigger update manually
sudo systemctl start xoa-xo-update.service
sudo systemctl start xoa-nixpkgs-update.service
sudo systemctl start xoa-gc.service

# Run GC only
sudo xoa-gc-generations

# Update specific input
sudo xoa-update-xoSrc-rebuild
sudo xoa-update-nixpkgs-rebuild
```

## Test Notifications

```bash
# Test ntfy
curl -H "Title: Test" -d "Testing XOA notifications" \
  https://ntfy.sh/YOUR-TOPIC

# Test email
echo "Test email body" | mail -s "XOA Test" admin@example.com

# Test webhook
curl -X POST "YOUR_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"subject":"Test","body":"Testing webhook","priority":"success"}'
```

## View Status Files

```bash
# List all status files
ls -la /var/lib/xoa-updates/

# View specific status
cat /var/lib/xoa-updates/xoSrc-update.status | jq

# Watch for changes
watch -n 5 'ls -lt /var/lib/xoa-updates/ | head'
```

## Troubleshooting

```bash
# Check why timer didn't run
sudo systemctl status xoa-xo-update.timer
journalctl -u xoa-xo-update.timer -e

# Check why service failed
sudo journalctl -u xoa-xo-update.service -e -p err

# Verify repository location
cd /etc/nixos/nixoa/nixoa-vm
git status

# Check network connectivity
curl -I https://github.com
curl -I https://ntfy.sh

# Test rebuild manually
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#xoa -L
```

## Enable/Disable Updates

```bash
# Disable specific timer
sudo systemctl disable --now xoa-xo-update.timer

# Enable specific timer
sudo systemctl enable --now xoa-xo-update.timer

# Stop all XOA timers
sudo systemctl stop xoa-*.timer

# Start all XOA timers
sudo systemctl start xoa-*.timer
```

## Monitoring Integration

```bash
# Export metrics (simple)
curl http://localhost:9100/metrics

# Check Prometheus scrape
curl http://prometheus:9090/api/v1/targets

# Force Prometheus reload
curl -X POST http://prometheus:9090/-/reload
```

## Emergency Procedures

```bash
# Rollback last update
sudo nixos-rebuild switch --rollback

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Boot into previous generation
sudo nixos-rebuild switch --rollback
sudo reboot

# Disable all automated updates
sudo systemctl disable xoa-*.timer
sudo systemctl stop xoa-*.timer
```

## Log Analysis

```bash
# Find failed updates in last 7 days
sudo journalctl -u 'xoa-*' --since '7 days ago' -p err

# Show update timeline
sudo journalctl -u 'xoa-*' --since yesterday -o short-iso

# Export logs
sudo journalctl -u xoa-xo-update.service > /tmp/xoa-logs.txt

# Follow all XOA services
sudo journalctl -f -u xoa-xo-update.service \
                   -u xoa-nixpkgs-update.service \
                   -u xoa-gc.service
```

## Performance Monitoring

```bash
# Check build times
journalctl -u xoa-xo-update.service | grep -i duration

# Disk space after GC
df -h /nix/store

# Generation sizes
nix-env --list-generations --profile /nix/var/nix/profiles/system | \
  while read gen; do
    echo "$gen: $(du -sh /nix/var/nix/profiles/system-*-link 2>/dev/null)"
  done

# Store optimization savings
nix-store --optimize --dry-run
```

## Configuration Validation

```bash
# Validate flake
nix flake check

# Validate TOML syntax
nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ~/user-config/configuration.nix)'

# Show current configuration
nix eval --json .#nixosConfigurations.nixoa.config.updates | jq

# Preview next update
nix flake lock --update-input xoSrc --dry-run
```

## Useful Aliases

Add to `~/.bashrc` or `/etc/profile`:

```bash
# XOA shortcuts
alias xoa-status='sudo xoa-update-status'
alias xoa-logs='sudo journalctl -u xoa-xo-update.service -u xoa-nixpkgs-update.service -f'
alias xoa-timers='systemctl list-timers "xoa-*"'
alias xoa-update='cd /etc/nixos/nixoa/nixoa-vm && sudo systemctl start xoa-xo-update.service'
alias xoa-rebuild='cd /etc/nixos/nixoa/nixoa-vm && sudo nixos-rebuild switch --flake .#xoa -L'
```

## Important Paths

```
~/user-config/                     # Your configuration (home directory)
  ├── configuration.nix         # System configuration file
  ├── config.nixoa.toml      # XO server configuration
  ├── hardware-configuration.nix   # Hardware configuration
  └── scripts/                     # Helper scripts

/etc/nixos/nixoa/
  ├── nixoa-vm/                    # Deployment flake repository
  └── user-config → ~/user-config  # Symlink to your configuration

/var/lib/xo/                       # XO application data
/etc/xo-server/config.toml         # XO configuration (auto-generated)
/var/log/journal/                  # Systemd logs
```

## Support Resources

- Status dashboard: `sudo xoa-update-status`
- Service logs: `sudo journalctl -u xoa-xo-update.service`
- Project repo: https://codeberg.org/nixoa/nixoa-vm
- NixOS manual: https://nixos.org/manual/nixos/stable/