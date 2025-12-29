# Getting Started with NiXOA

Get NiXOA installed and deployed in about 5 minutes.

## Prerequisites

- A NixOS VM or physical machine
- Internet connection
- SSH access (or local console)
- Basic Linux comfort

## Installation (3 minutes)

### Automated Installation (Recommended)

```bash
# Run this as a regular user (not root)
bash <(curl -fsSL https://codeberg.org/nixoa/nixoa-vm/raw/main/scripts/xoa-install.sh)
```

The installer will:
1. Clone NiXOA modules to `/etc/nixos/nixoa-vm`
2. Clone your config to `~/user-config`
3. Generate initial configuration files
4. Guide you through next steps

### Manual Installation

If you prefer more control:

```bash
# Clone the modules (as root)
sudo mkdir -p /etc/nixos/nixoa
sudo git clone https://codeberg.org/nixoa/nixoa-vm.git /etc/nixos/nixoa-vm

# Clone your configuration (as regular user)
git clone https://codeberg.org/nixoa/user-config.git ~/user-config
cd ~/user-config
```

See [Installation Guide](./installation.md) for detailed steps.

## Configuration (1 minute)

Edit `~/user-config/configuration.nix`:

```bash
nano ~/user-config/configuration.nix
```

**Required changes in `systemSettings`:**
- `hostname` - Your system name
- `username` - Admin user (usually `xoa`)
- `sshKeys` - Add your SSH public key

**Example:**
```nix
systemSettings = {
  hostname = "my-xoa";
  username = "xoa";
  timezone = "UTC";
  sshKeys = [ "ssh-ed25519 AAAAC3..." ];
};
```

See [Configuration Guide](./configuration.md) for full options.

## Deployment (1 minute)

```bash
cd ~/user-config
./scripts/apply-config "Initial deployment"
```

This commits your changes and rebuilds the system. Grab coffee—this takes a few minutes on first run.

## Access Xen Orchestra

After deployment completes:

```
HTTPS: https://YOUR-IP/
HTTP:  https://YOUR-IP/ (HTTP redirects to HTTPS)
v6 UI: https://YOUR-IP/v6

Default login:
  Username: admin@admin.net
  Password: admin

⚠️ Change the password immediately!
```

## What's Next?

- **Managing your system**: [Daily Operations](./operations.md)
- **Common configuration changes**: [Common Tasks](./common-tasks.md)
- **Understand the architecture**: [Architecture Guide](./architecture.md)
- **Something broken**: [Troubleshooting Guide](./troubleshooting.md)

## Quick Sanity Checks

```bash
# Is XO running?
sudo systemctl status xo-server.service

# View recent logs
sudo journalctl -u xo-server -n 20

# Test connection
curl -k https://localhost/
```

## Need Help?

- Check [Troubleshooting Guide](./troubleshooting.md)
- Review [Configuration Guide](./configuration.md)
- Visit [Issues](https://codeberg.org/nixoa/nixoa-vm/issues)
