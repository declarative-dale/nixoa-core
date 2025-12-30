# Installation Guide

Detailed instructions for installing NiXOA on NixOS.

## System Requirements

- NixOS (latest stable recommended, 23.11+)
- 2+ CPU cores
- 4GB RAM minimum (8GB recommended)
- 20GB disk space minimum
- Internet connection

## Installation Methods

### Method 1: Automated Installation Script (Recommended)

```bash
bash <(curl -fsSL https://codeberg.org/nixoa/nixoa-vm/raw/main/scripts/xoa-install.sh)
```

Or download and run locally:

```bash
git clone https://codeberg.org/nixoa/nixoa-vm.git
cd nixoa-vm/scripts
bash xoa-install.sh
```

**What the script does:**
1. Creates `/etc/nixos/nixoa/` directory
2. Clones nixoa-vm to `/etc/nixos/nixoa-vm`
3. Clones user-config to `~/user-config`
4. Generates initial `configuration.nix` if missing
5. Generates `hardware-configuration.nix` if missing
6. Initializes git repository
7. Provides next steps

### Method 2: Manual Installation

#### Step 1: Clone NiXOA Modules

```bash
# Create the system directory
sudo mkdir -p /etc/nixos/nixoa
cd /etc/nixos/nixoa

# Clone the module library
sudo git clone https://codeberg.org/nixoa/nixoa-vm.git
```

Verify clone:
```bash
ls -la /etc/nixos/nixoa-vm/
```

#### Step 2: Clone User Configuration

```bash
# Clone to your home directory
git clone https://codeberg.org/nixoa/user-config.git ~/user-config
cd ~/user-config
```

#### Step 3: Copy Hardware Configuration

NixOS generates a hardware configuration during installation. Copy it:

```bash
sudo cp /etc/nixos/hardware-configuration.nix ~/user-config/
sudo chown $USER:$USER ~/user-config/hardware-configuration.nix
```

Add to git:
```bash
cd ~/user-config
git add hardware-configuration.nix
git commit -m "Add hardware configuration"
```

#### Step 4: Generate Initial Configuration

If `configuration.nix` doesn't exist, create it:

```bash
cat > ~/user-config/configuration.nix <<'EOF'
{ lib, pkgs, ... }:

{
  userSettings = {
    packages.extra = [];
    extras.enable = false;
  };

  systemSettings = {
    # CHANGE THESE VALUES
    hostname = "nixoa";
    username = "xoa";
    timezone = "UTC";
    sshKeys = [
      # Paste your SSH public key here
      # ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...
    ];

    xo.port = 80;
    xo.httpsPort = 443;

    storage.nfs.enable = true;
    storage.cifs.enable = true;
  };
}
EOF
```

#### Step 5: Create Git Repository

Initialize version control:

```bash
cd ~/user-config
git add .
git commit -m "Initial NiXOA configuration"
```

## First Deployment

### 1. Edit Configuration

```bash
cd ~/user-config
nano configuration.nix
```

**Required changes in `systemSettings`:**
- Set your `hostname`
- Set your `username`
- Add your SSH public key to `sshKeys`
- Verify `timezone` is correct

### 2. Apply Configuration

```bash
cd ~/user-config
./scripts/apply-config "Initial deployment"
```

This will:
1. Validate your configuration
2. Build the NixOS system
3. Switch to the new system generation
4. Restart services

**First deployment takes 5-15 minutes** (building from scratch).

### 3. Verify Installation

After deployment completes:

```bash
# Check XO is running
sudo systemctl status xo-server.service

# Check Redis is running
sudo systemctl status redis-xo.service

# View recent logs
sudo journalctl -u xo-server -n 30 -f
```

## Verification Checklist

- [ ] NiXOA modules cloned to `/etc/nixos/nixoa-vm`
- [ ] User configuration cloned to `~/user-config`
- [ ] Hardware configuration copied
- [ ] `configuration.nix` has valid settings
- [ ] `apply-config` completed without errors
- [ ] Can connect to `https://localhost/`
- [ ] Can SSH to the system

## Troubleshooting Installation

### Clone Failed

```bash
# Check git is installed
git --version

# Try clone again
git clone https://codeberg.org/nixoa/user-config.git ~/user-config
```

### Hardware Configuration Not Found

```bash
# Check if it exists
ls -la /etc/nixos/hardware-configuration.nix

# Generate it if missing
sudo nixos-generate-config --root /
sudo cp /etc/nixos/hardware-configuration.nix ~/user-config/
```

### Deployment Failed

```bash
# Check configuration syntax
cd ~/user-config
nix flake check .

# Try rebuild manually
sudo nixos-rebuild switch --flake .#HOSTNAME -L

# Check logs
journalctl -xe
```

### Permission Denied on Scripts

```bash
chmod +x ~/user-config/scripts/*.sh
chmod +x ~/user-config/commit-config ~/user-config/apply-config ~/user-config/show-diff ~/user-config/history
```

## Next Steps

- **[Configuration Guide](./configuration.md)** - Configure all options
- **[Daily Operations](./operations.md)** - How to manage your system
- **[Getting Started](./getting-started.md)** - Quick reference
