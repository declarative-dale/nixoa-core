# Configuration Guide

This flake uses a **TOML configuration file** for all personal settings. This keeps your personal information separate from the flake code and allows the flake to be updated without conflicts.

## Quick Start

1. **Copy the sample configuration:**
   ```bash
   cp sample-nixoa.toml nixoa.toml
   ```

2. **Edit `nixoa.toml` with your settings:**
   ```bash
   nano nixoa.toml  # or use your preferred editor
   ```

3. **Configure at minimum:**
   - `hostname` - Your system's hostname
   - `username` - Your admin username
   - `sshKeys` - Array of your SSH public keys (generate with `ssh-keygen -t ed25519`)
   - `timezone` - Your timezone (e.g., `America/New_York`, `Europe/London`)

4. **Build and deploy:**
   ```bash
   sudo nixos-rebuild switch --flake .#your-hostname
   ```

## How It Works

### File Structure

- **`nixoa.toml`** - Your personal configuration (git-ignored, NEVER committed)
- **`sample-nixoa.toml`** - Template with all available options and defaults
- **`vars.nix`** - Reads nixoa.toml using `builtins.fromTOML` and provides values to the flake

### Configuration Flow

```
nixoa.toml (your personal config)
  ↓
vars.nix (reads via builtins.fromTOML)
  ↓
flake.nix → modules/*.nix (uses vars)
```

## Key Benefits

✅ **Nix-native**: Uses built-in `builtins.fromTOML` (no custom parser)
✅ **Type-safe**: Real booleans, numbers, arrays, objects
✅ **Hierarchical**: Natural nested structure with dotted keys
✅ **Git-safe**: `nixoa.toml` is automatically ignored by git
✅ **Flexible**: All .nix files can be updated freely without conflicts
✅ **Human-readable**: Clean TOML format with native comment support

## Configuration Options

### Example nixoa.toml

```toml
hostname = "xoa"
username = "admin"
timezone = "UTC"

sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... user@laptop"
]

[xo]
host = "0.0.0.0"
port = 80
httpsPort = 443
enableV6Preview = false

[tls]
enable = true
redirectToHttps = true

[networking.firewall]
allowedTCPPorts = [80, 443, 3389, 5900, 8012]

[storage]
mountsDir = "/var/lib/xo/mounts"

[storage.nfs]
enable = true

[storage.cifs]
enable = true

[updates.gc]
enable = true
schedule = "Sun 04:00"
keepGenerations = 7
```

### Required Settings

| Key | Type | Description | Example |
|-----|------|-------------|---------|
| `hostname` | string | System hostname | `"xoa"` |
| `username` | string | Admin username | `"admin"` |
| `timezone` | string | System timezone | `"UTC"` or `"America/New_York"` |
| `sshKeys` | array | SSH public keys | `["ssh-ed25519 AAAA..."]` |

### SSH Keys

Add multiple SSH keys as an array:

```toml
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... alice@laptop",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcd... bob@desktop",
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... charlie@phone"
]
```

TOML supports native comments with `#`:

```toml
# Add your SSH public keys here
sshKeys = [
  "ssh-ed25519 AAAAC3... your-key-here"
]
```

### Web Interface Settings

```toml
[xo]
host = "0.0.0.0"        # 0.0.0.0 = all interfaces, 127.0.0.1 = localhost only
port = 80               # HTTP port
httpsPort = 443         # HTTPS port
enableV6Preview = false # Enable XO v6 preview at /v6

[tls]
enable = true              # Auto-generate self-signed certificates
redirectToHttps = true     # Redirect HTTP to HTTPS
dir = "/etc/ssl/xo"        # Certificate directory
cert = "/etc/ssl/xo/certificate.pem"
key = "/etc/ssl/xo/key.pem"
```

### Firewall

```toml
[networking.firewall]
allowedTCPPorts = [
  80,    # HTTP
  443,   # HTTPS
  3389,  # RDP console
  5900,  # VNC console
  8012   # XO service port
]
```

### Storage

```toml
[storage]
mountsDir = "/var/lib/xo/mounts"

[storage.nfs]
enable = true    # Enable NFS remote storage

[storage.cifs]
enable = true    # Enable CIFS/SMB remote storage
```

### Automated Updates

Configure automatic updates for different components:

**Garbage Collection:**
```toml
[updates.gc]
enable = true
schedule = "Sun 04:00"
keepGenerations = 7
```

**Flake Self-Update:**
```toml
[updates.flake]
enable = true
schedule = "Sun 04:00"
remoteUrl = "https://codeberg.org/dalemorgan/declarative-xoa-ce.git"
branch = "main"
autoRebuild = false
```

**Component Updates:**
```toml
[updates.nixpkgs]
enable = true
schedule = "Mon 04:00"
keepGenerations = 7

[updates.xoa]
enable = true
schedule = "Tue 04:00"
keepGenerations = 7

[updates.libvhdi]
enable = true
schedule = "Wed 04:00"
keepGenerations = 7
```

### Notifications

**Email:**
```toml
[updates.monitoring]
notifyOnSuccess = false

[updates.monitoring.email]
enable = true
to = "admin@example.com"
```

**ntfy.sh Push Notifications:**
```toml
[updates.monitoring.ntfy]
enable = true
server = "https://ntfy.sh"
topic = "my-unique-topic-name"
```

**Webhook:**
```toml
[updates.monitoring.webhook]
enable = true
url = "https://hooks.example.com/webhook"
```

### Terminal Enhancements

```toml
[extras]
enable = false  # Enable enhanced terminal (zsh, oh-my-posh, fzf, etc.)
```

### Service Account

```toml
[service]
xoUser = "xo"    # Rarely needs changing
xoGroup = "xo"
```

### Custom Packages

Add extra packages to your system or user account:

**System Packages (available to all users):**
```toml
[packages.system]
extra = ["neovim", "ripgrep", "fd", "jq", "docker-compose"]
```

**User Packages (only for admin user):**
```toml
[packages.user]
extra = ["lazygit", "fzf", "bat", "zoxide"]
```

Package names should match nixpkgs attribute names. Search available packages at [search.nixos.org](https://search.nixos.org/packages).

### Custom Services

Enable and configure NixOS services:

**Simple Enable (uses defaults):**
```toml
[services]
enable = ["docker", "tailscale", "fail2ban"]
```

**Configure with Options:**
```toml
# Simple enable list for services with defaults
[services]
enable = ["tailscale"]

# Detailed configuration for specific services
[services.docker]
enable = true
enableOnBoot = true

[services.docker.autoPrune]
enable = true
dates = "weekly"

[services.postgresql]
enable = true
package = "postgresql_15"
enableTCPIP = true
port = 5432

[services.fail2ban]
enable = true
maxretry = 5
bantime = "10m"
```

**Common Services:**
- `docker` - Container runtime
- `tailscale` - Zero-config VPN
- `fail2ban` - Intrusion prevention
- `postgresql` - SQL database
- `mysql` - SQL database
- `redis` - Key-value store
- `prometheus` - Monitoring system
- `grafana` - Metrics dashboard

See [search.nixos.org/options](https://search.nixos.org/options) for all available services and their options.

### State Version

```toml
stateVersion = "25.05"  # DO NOT CHANGE after initial installation
```

## TOML Tips

### Validation

Validate your TOML before rebuilding:

```bash
# Nix can validate TOML directly
nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ./nixoa.toml)'

# Or use a TOML validator if available
toml-cli check nixoa.toml  # if you have toml-cli installed
```

### Comments

TOML has native comment support with `#`:

```toml
# This is a comment
hostname = "xoa"

# Ports below 1024 require root
[xo]
port = 80
```

### Default Values

If you omit a setting from `nixoa.toml`, the default value from `sample-nixoa.toml` is used. You only need to specify settings you want to change.

**Minimal nixoa.toml:**
```toml
hostname = "my-xoa"
username = "admin"
timezone = "America/New_York"

sshKeys = [
  "ssh-ed25519 AAAAC3... user@host"
]
```

All other settings will use defaults!

## Updating the Flake

With this configuration system, you can safely update the flake without losing your settings:

```bash
# Pull latest changes from upstream
cd ~/nixoa
git pull origin main

# Your nixoa.toml is never touched by git
# No merge conflicts!

# Rebuild with your existing configuration
sudo nixos-rebuild switch --flake .#$(hostname)
```

## Troubleshooting

### Configuration not taking effect

Make sure your `nixoa.toml`:
- Is in the flake root directory (same directory as `flake.nix`)
- Is valid TOML (use `nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ./nixoa.toml)'` to validate)
- Uses proper types (booleans are `true`/`false`, not `"true"`/`"false"`)

### TOML syntax errors

Common TOML issues:
- ❌ Missing quotes on strings: `hostname = xoa`
- ✅ Quoted strings: `hostname = "xoa"`
- ❌ Wrong array syntax: `ports = 80, 443`
- ✅ Correct array syntax: `ports = [80, 443]`
- ✅ Comments use #: `port = 80  # HTTP port`

Validate with Nix:
```bash
nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ./nixoa.toml)' || echo "Invalid TOML!"
```

### SSH keys not working

Ensure:
- Keys are in an array: `["key1", "key2"]`
- Keys start with `ssh-ed25519`, `ssh-rsa`, etc.
- Keys are strings with double quotes
- No extra spaces or newlines within the key string

### Checking current configuration

Verify vars.nix is reading your nixoa.toml correctly:

```bash
# Check hostname
nix eval .#nixosConfigurations.xoa.config.networking.hostName

# Check timezone
nix eval .#nixosConfigurations.xoa.config.time.timeZone

# Check if flake loads
nix flake show
```

## Security Notes

⚠️ **Important Security Considerations:**

- `nixoa.toml` contains sensitive information (SSH keys, API tokens, etc.)
- Never commit `nixoa.toml` to git (it's in `.gitignore`)
- Keep backups of `nixoa.toml` in a secure location
- Set appropriate file permissions: `chmod 600 nixoa.toml`
- Use SSH keys, not passwords
- Review `sample-nixoa.toml` to understand all options

## Support

For issues or questions:
- Check `sample-nixoa.toml` for all available options
- Review `vars.nix` to see how defaults are handled
- Validate TOML with `nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ./nixoa.toml)'`
- See main README.md for general flake documentation
