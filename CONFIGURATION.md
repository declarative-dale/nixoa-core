<!-- SPDX-License-Identifier: Apache-2.0 -->
# Configuration Guide

NiXOA uses a **dual-flake architecture** where configuration is managed separately from deployment. Your personal configuration lives in `~/user-config` (your home directory) and the deployment code lives in `/etc/nixos/nixoa/nixoa-vm` (system directory).

This separation ensures:
- ✅ Configuration stays in your home directory (user-owned)
- ✅ Deployment code can be updated without touching your settings
- ✅ No merge conflicts when updating the flake
- ✅ Git-friendly: version control your config separately

---

## Initial Setup

### 1. Clone Configuration Flake

```bash
# As a regular user, clone to your home directory
git clone https://codeberg.org/nixoa/user-config.git ~/user-config
cd ~/user-config
```

### 2. Edit Configuration Files

```bash
# Edit your system configuration
nano configuration.nix
```

**Required minimum settings:**
- `hostname` - Your system's hostname
- `username` - Admin user for SSH access
- `sshKeys` - Your SSH public key(s)

### 3. Create System Symlink

The flake input path must be absolute, so we use a symlink:

```bash
sudo mkdir -p /etc/nixos/nixoa
sudo ln -sf ~/user-config /etc/nixos/nixoa/user-config
```

This allows the flake to find your config while you edit it in your home directory.

### 4. Copy Hardware Configuration

```bash
# Copy or generate hardware configuration
sudo cp /etc/nixos/hardware-configuration.nix ~/user-config/
sudo chown $USER:$USER ~/user-config/hardware-configuration.nix

# Or generate a fresh one
sudo nixos-generate-config --show-hardware-config > ~/user-config/hardware-configuration.nix
```

### 5. Deploy

```bash
# Commit your initial configuration
cd ~/user-config
./scripts/commit-config.sh "Initial configuration"

# Build and deploy
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#<hostname>
```

Replace `<hostname>` with the value you set in `configuration.nix`.

---

## Directory Structure

```
/home/<user>/
└── user-config/                      # Your configuration flake
    ├── flake.nix                     # Flake inputs/outputs
    ├── configuration.nix             # Your system configuration (Nix format)
    ├── config.nixoa.toml             # XO service overrides (TOML format)
    ├── hardware-configuration.nix    # Your hardware config
    ├── modules/
    │   └── home.nix                  # Home Manager configuration
    └── scripts/
        ├── commit-config.sh          # Git commit helper
        ├── apply-config.sh           # Commit + rebuild
        ├── show-diff.sh              # Show pending changes
        └── history.sh                # Show configuration history

/etc/nixos/nixoa/
├── nixoa-vm/                         # Deployment flake (from repo)
│   ├── flake.nix
│   ├── flake.lock
│   ├── modules/                      # Core system modules
│   │   ├── nixoa-options.nix         # Option definitions
│   │   ├── xoa.nix                   # XO service setup
│   │   ├── system.nix                # System configuration
│   │   ├── storage.nix               # NFS/CIFS support
│   │   ├── libvhdi.nix               # VHD tools
│   │   ├── autocert.nix              # TLS certificate generation
│   │   └── updates.nix               # Update automation
│   └── scripts/
│       ├── xoa-install.sh            # Initial install
│       ├── xoa-logs.sh               # View service logs
│       └── xoa-update.sh             # Manual XO update
│
└── user-config → /home/<user>/user-config  # Symlink to your home config
```

---

## Configuration File Format

### configuration.nix

This is the main configuration file. It uses Nix format and exports configuration as a set with `userSettings` and `systemSettings`.

**Example minimal configuration:**

```toml
# System basics (required)
hostname = "nixoa"
stateVersion = "25.11"

[admin]
username = "xoa"
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... user@laptop"
]

# Xen Orchestra web interface (optional - defaults shown)
[xo]
host = "0.0.0.0"
port = 80
httpsPort = 443

# TLS/HTTPS settings
[tls]
enable = true
redirectToHttps = true
autoGenerate = true
cert = "/etc/ssl/xo/certificate.pem"
key = "/etc/ssl/xo/key.pem"

# Remote storage support
[storage.nfs]
enable = true

[storage.cifs]
enable = true

[storage.vhd]
enable = true
mountsDir = "/var/lib/xo/mounts"

# Firewall rules
[networking.firewall]
allowedTCPPorts = [80, 443, 3389, 5900, 8012]
```

---

## Configuration Options

### System Basics

```toml
hostname = "nixoa"                    # System hostname (used in flake output)
stateVersion = "25.11"                # NixOS state version (DO NOT CHANGE)
```

### Admin User

```toml
[admin]
username = "xoa"                      # Admin user account name
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...",
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB..."
]
```

**Generate SSH keys:**
```bash
# ED25519 (preferred)
ssh-keygen -t ed25519 -C "user@host"

# Or RSA (older systems)
ssh-keygen -t rsa -b 4096 -C "user@host"
```

### Xen Orchestra Web Interface

```toml
[xo]
host = "0.0.0.0"                      # All interfaces (or "127.0.0.1" for localhost)
port = 80                             # HTTP port (requires no special privileges)
httpsPort = 443                       # HTTPS port (requires no special privileges in systemd)

[xo.service]
xoUser = "xo"                         # Service user (rarely needs changing)
xoGroup = "xo"                        # Service group
```

### TLS/HTTPS Configuration

```toml
[tls]
enable = true                         # Enable HTTPS
redirectToHttps = true                # Redirect HTTP → HTTPS
autoGenerate = true                   # Auto-generate self-signed certs
dir = "/etc/ssl/xo"                   # Certificate directory
cert = "/etc/ssl/xo/certificate.pem"  # Certificate file path
key = "/etc/ssl/xo/key.pem"           # Private key file path
```

**Using Let's Encrypt instead:**

To use proper certificates, edit the NixOS configuration directly (advanced):

```bash
# Edit flake modules or add a custom NixOS module
sudo nano /etc/nixos/configuration.nix
```

### Storage Support

```toml
[storage]
mountsDir = "/var/lib/xo/mounts"      # Where remote storage mounts live

[storage.nfs]
enable = true                         # Enable NFS remote storage mounting

[storage.cifs]
enable = true                         # Enable CIFS/SMB remote storage mounting

[storage.vhd]
enable = true                         # Enable VHD/VHDX image support
```

### Firewall Rules

```toml
[networking.firewall]
allowedTCPPorts = [
  80,                                 # HTTP
  443,                                # HTTPS
  3389,                               # RDP console access
  5900,                               # VNC console access
  8012                                # XO service port
]
```

### Automated Updates

Configure automatic updates for your system components:

```toml
[updates]
repoDir = "/etc/nixos/nixoa/nixoa-vm"  # Path to nixoa-vm clone

# Garbage collection
[updates.gc]
enable = true
schedule = "Sun *-*-* 04:00:00"       # Run Sunday at 4 AM
keepGenerations = 7

# Flake self-update (update nixoa-vm from repo)
[updates.flake]
enable = true
schedule = "Sun *-*-* 05:00:00"
remoteUrl = "https://codeberg.org/nixoa/nixoa-vm.git"
branch = "main"
autoRebuild = false

# NixOS packages update
[updates.nixpkgs]
enable = true
schedule = "Mon *-*-* 04:00:00"
keepGenerations = 7

# Xen Orchestra source update
[updates.xoa]
enable = true
schedule = "Tue *-*-* 04:00:00"
keepGenerations = 7
```

### System Packages

```toml
# System-wide packages (available to all users)
[packages.system]
extra = [
  "htop",
  "tmux",
  "vim",
  "ripgrep"
]

# Admin user packages (only for admin account)
[packages.user]
extra = [
  "lazygit",
  "fzf",
  "bat"
]
```

Find package names at [search.nixos.org/packages](https://search.nixos.org/packages).

### Custom Services

Enable NixOS services directly:

```toml
# Simple enable (uses defaults)
[services]
enable = ["docker", "fail2ban"]

# Configure docker with custom options
[services.docker]
enable = true
enableOnBoot = true

[services.docker.autoPrune]
enable = true
dates = "weekly"
```

Common services:
- `docker` - Container runtime
- `fail2ban` - Intrusion prevention
- `postgresql` - PostgreSQL database
- `mysql` - MySQL database
- `redis` - Redis cache
- `tailscale` - VPN
- `prometheus` - Monitoring
- `grafana` - Metrics dashboard

### Terminal Enhancements

```toml
[extras]
enable = false                        # Enable zsh, oh-my-posh, fzf, etc.
```

---

## Configuration Workflow

### Making Changes

1. **Edit your configuration:**
   ```bash
   cd ~/user-config
   nano configuration.nix
   ```

2. **Review changes:**
   ```bash
   ./scripts/show-diff.sh    # or: git diff
   ```

3. **Commit and apply:**
   ```bash
   ./scripts/apply-config.sh "Describe your changes"
   ```

   This will:
   - Commit changes to git
   - Run `sudo nixos-rebuild switch` with your hostname
   - Apply the configuration to the system

### Manual Apply (Advanced)

If you prefer more control:

```bash
# Just commit
./scripts/commit-config.sh "Your message"

# Later, rebuild separately
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#<hostname> -L
```

### Viewing History

```bash
cd ~/user-config

# See recent changes
git log --oneline -10

# See full diff of a commit
git show <commit-hash>

# Revert to a previous version
git checkout <commit-hash> -- configuration.nix config.nixoa.toml
```

---

## Troubleshooting

### TOML Validation

Validate your TOML syntax before rebuilding:

```bash
# Validate with Nix
nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ~/user-config/configuration.nix)'

# If valid, returns the config as Nix attributes
# If invalid, shows TOML parse error
```

### Common TOML Mistakes

❌ **Wrong:** `hostname = xoa` (missing quotes)
✅ **Right:** `hostname = "xoa"`

❌ **Wrong:** `allowedTCPPorts = 80, 443` (not an array)
✅ **Right:** `allowedTCPPorts = [80, 443]`

❌ **Wrong:** `sshKeys = ["key", "key2",]` (trailing comma)
✅ **Right:** `sshKeys = ["key", "key2"]`

### Configuration Not Taking Effect

1. Check if changes are committed:
   ```bash
   cd ~/user-config
   git status
   ```

2. Validate TOML:
   ```bash
   nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ~/user-config/configuration.nix)'
   ```

3. Check flake can load:
   ```bash
   cd /etc/nixos/nixoa/nixoa-vm
   nix flake show
   ```

4. Manual rebuild:
   ```bash
   sudo nixos-rebuild switch --flake .#<hostname> -L --show-trace
   ```

### SSH Keys Not Working

Ensure:
- Keys are in proper format: `ssh-ed25519 AAAA...` or `ssh-rsa AAAA...`
- Keys are in an array: `["key1", "key2"]`
- No extra whitespace or newlines
- File permissions correct: `sudo chmod 600 ~/.ssh/authorized_keys`

### Symlink Issues

If the symlink is broken:

```bash
# Check symlink
ls -la /etc/nixos/nixoa/user-config

# Recreate if needed
sudo rm /etc/nixos/nixoa/user-config
sudo ln -sf ~/user-config /etc/nixos/nixoa/user-config

# Verify
ls -la /etc/nixos/nixoa/user-config
```

### Can't Edit Config

If you can't edit files in `~/user-config`:

```bash
# Verify ownership
ls -la ~/user-config/configuration.nix

# Fix if needed
chown $USER:$USER ~/user-config/configuration.nix

# Check permissions
chmod 644 ~/user-config/configuration.nix
```

### Rebuild Fails

Check detailed error output:

```bash
cd /etc/nixos/nixoa/nixoa-vm
sudo nixos-rebuild switch --flake .#<hostname> -L --show-trace 2>&1 | tail -100
```

Common issues:
- Missing hardware-configuration.nix
- Invalid TOML syntax
- Package name doesn't exist
- Hostname mismatch between config and command

---

## Advanced: Updating While Preserving Config

Since your config is separate, you can safely update nixoa-vm:

```bash
# Update the deployment flake
cd /etc/nixos/nixoa/nixoa-vm
git pull origin main

# Your ~/user-config is untouched!

# Rebuild with your existing config
sudo nixos-rebuild switch --flake .#<hostname>
```

No merge conflicts, no lost settings!

---

## See Also

- [README.md](README.md) - Main documentation and troubleshooting
- [user-config/README.md](../user-config/README.md) - User configuration flake docs
- [MIGRATION-OPTIONS.md](MIGRATION-OPTIONS.md) - Complete options reference
