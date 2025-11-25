# Configuration Guide

This flake now uses a `.env` file for all personal configuration settings. This keeps your personal information separate from the flake code and allows the flake to be updated without conflicts.

## Quick Start

1. **Copy the sample configuration:**
   ```bash
   cp sample.env .env
   ```

2. **Edit `.env` with your settings:**
   ```bash
   nano .env  # or use your preferred editor
   ```

3. **Configure at minimum:**
   - `HOSTNAME` - Your system's hostname
   - `USERNAME` - Your admin username
   - `SSH_KEY_1` - Your SSH public key (generate with `ssh-keygen -t ed25519`)
   - `TIMEZONE` - Your timezone (e.g., `America/New_York`, `Europe/London`)

4. **Build and deploy:**
   ```bash
   sudo nixos-rebuild switch --flake .#your-hostname
   ```

## How It Works

### File Structure

- **`.env`** - Your personal configuration (git-ignored, NEVER committed)
- **`sample.env`** - Template with all available options and defaults
- **`vars.nix`** - Reads `.env` and provides values to the flake (can be updated)
- **`lib.nix`** - Helper functions for parsing `.env` files

### Configuration Flow

```
.env (your personal config)
  ↓
vars.nix (reads .env using lib.nix)
  ↓
flake.nix → modules/*.nix (uses vars)
```

## Key Benefits

✅ **Separation of Concerns**: Personal info stays in `.env`, code stays in `.nix` files
✅ **Easy Updates**: Pull flake updates without merge conflicts
✅ **Git-Safe**: `.env` is automatically ignored by git
✅ **Flexible**: All .nix files can now be updated freely

## Configuration Options

### Required Settings

| Variable | Description | Example |
|----------|-------------|---------|
| `HOSTNAME` | System hostname | `xoa` |
| `USERNAME` | Admin username | `admin` |
| `SSH_KEY_1` | SSH public key | `ssh-ed25519 AAAA...` |
| `TIMEZONE` | System timezone | `UTC` or `America/New_York` |

### SSH Keys

Add multiple SSH keys by using numbered variables:

```bash
SSH_KEY_1=ssh-ed25519 AAAAC3... user@laptop
SSH_KEY_2=ssh-rsa AAAAB3... user@desktop
SSH_KEY_3=ssh-ed25519 AAAAC3... user@phone
```

The system automatically collects `SSH_KEY_1` through `SSH_KEY_10`.

### Web Interface Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `XO_HOST` | `0.0.0.0` | Network binding (0.0.0.0 = all interfaces) |
| `XO_PORT` | `80` | HTTP port |
| `XO_HTTPS_PORT` | `443` | HTTPS port |
| `TLS_ENABLE` | `true` | Enable auto-generated self-signed certs |
| `TLS_REDIRECT_TO_HTTPS` | `true` | Redirect HTTP to HTTPS |
| `ENABLE_V6_PREVIEW` | `false` | Enable XO v6 preview at /v6 |

### Firewall

`FIREWALL_TCP_PORTS` accepts a comma-separated list of ports:

```bash
FIREWALL_TCP_PORTS=80,443,3389,5900,8012
```

### Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_NFS_ENABLE` | `true` | Enable NFS remote storage |
| `STORAGE_CIFS_ENABLE` | `true` | Enable CIFS/SMB remote storage |
| `STORAGE_MOUNTS_DIR` | `/var/lib/xo/mounts` | Mount point directory |

### Updates

Configure automatic updates for different components:

**Garbage Collection:**
```bash
UPDATES_GC_ENABLE=true
UPDATES_GC_SCHEDULE="Sun 04:00"
UPDATES_GC_KEEP_GENERATIONS=7
```

**Flake Self-Update:**
```bash
UPDATES_FLAKE_ENABLE=true
UPDATES_FLAKE_SCHEDULE="Sun 04:00"
UPDATES_FLAKE_REMOTE_URL=https://codeberg.org/dalemorgan/declarative-xoa-ce.git
UPDATES_FLAKE_BRANCH=main
UPDATES_FLAKE_AUTO_REBUILD=false
```

**Component Updates:**
```bash
# NixOS/nixpkgs
UPDATES_NIXPKGS_ENABLE=true
UPDATES_NIXPKGS_SCHEDULE="Mon 04:00"
UPDATES_NIXPKGS_KEEP_GENERATIONS=7

# Xen Orchestra
UPDATES_XOA_ENABLE=true
UPDATES_XOA_SCHEDULE="Tue 04:00"
UPDATES_XOA_KEEP_GENERATIONS=7

# libvhdi
UPDATES_LIBVHDI_ENABLE=true
UPDATES_LIBVHDI_SCHEDULE="Wed 04:00"
UPDATES_LIBVHDI_KEEP_GENERATIONS=7
```

### Notifications

**Email:**
```bash
UPDATES_EMAIL_ENABLE=true
UPDATES_EMAIL_TO=admin@example.com
```

**ntfy.sh Push Notifications:**
```bash
UPDATES_NTFY_ENABLE=true
UPDATES_NTFY_SERVER=https://ntfy.sh
UPDATES_NTFY_TOPIC=my-unique-topic-name
```

**Webhook:**
```bash
UPDATES_WEBHOOK_ENABLE=true
UPDATES_WEBHOOK_URL=https://hooks.example.com/webhook
```

## Advanced Configuration

### Boolean Values

Boolean values can be set using any of these formats:
- `true`, `TRUE`, `1`, `yes`, `YES` → true
- `false`, `FALSE`, `0`, `no`, `NO` → false

### Integer Values

Integer values are parsed automatically:
```bash
XO_PORT=8080
UPDATES_GC_KEEP_GENERATIONS=10
```

### List Values

Lists use comma-separated values:
```bash
FIREWALL_TCP_PORTS=80,443,8080,8443
```

### Default Values

If a variable is not set in `.env`, the system uses the default value specified in `sample.env`. You can see all defaults by reviewing `sample.env`.

## Updating the Flake

With this new configuration system, you can safely update the flake without losing your settings:

```bash
# Pull latest changes from upstream
git pull origin main

# Your .env file is never touched by git
# No merge conflicts!

# Rebuild with your existing configuration
sudo nixos-rebuild switch --flake .#$(hostname)
```

## Migrating from Old Configuration

If you're migrating from the old `vars.nix` configuration:

1. Create `.env` from `sample.env`
2. Copy your settings from old `vars.nix` to `.env`
3. The new `vars.nix` will automatically read from `.env`
4. Old `vars.nix` configurations work as defaults if `.env` is missing

## Troubleshooting

### Configuration not taking effect

Make sure your `.env` file:
- Is in the flake root directory (same directory as `flake.nix`)
- Has proper syntax (no spaces around `=`, no trailing spaces)
- Uses valid values (check `sample.env` for examples)

### SSH keys not working

Ensure:
- Keys start with `ssh-ed25519`, `ssh-rsa`, etc.
- No extra quotes around the key
- Key format: `SSH_KEY_1=ssh-ed25519 AAAAC3... user@host`

### Checking current configuration

You can verify vars.nix is reading your .env correctly:

```bash
nix eval .#nixosConfigurations.$(hostname).config.networking.hostName
nix eval .#nixosConfigurations.$(hostname).config.time.timeZone
```

## Security Notes

⚠️ **Important Security Considerations:**

- `.env` contains sensitive information (SSH keys, API tokens, etc.)
- Never commit `.env` to git (it's in `.gitignore`)
- Keep backups of `.env` in a secure location
- Set appropriate file permissions: `chmod 600 .env`
- Use SSH keys, not passwords

## Support

For issues or questions:
- Check `sample.env` for all available options
- Review `vars.nix` for default values
- See main README.md for general flake documentation
