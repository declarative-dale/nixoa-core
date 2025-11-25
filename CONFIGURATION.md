# Configuration Guide

This flake uses a **JSON configuration file** for all personal settings. This keeps your personal information separate from the flake code and allows the flake to be updated without conflicts.

## Quick Start

1. **Copy the sample configuration:**
   ```bash
   cp config.sample.json config.json
   ```

2. **Edit `config.json` with your settings:**
   ```bash
   nano config.json  # or use your preferred editor
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

- **`config.json`** - Your personal configuration (git-ignored, NEVER committed)
- **`config.sample.json`** - Template with all available options and defaults
- **`vars.nix`** - Reads config.json using `builtins.fromJSON` and provides values to the flake

### Configuration Flow

```
config.json (your personal config)
  ↓
vars.nix (reads via builtins.fromJSON)
  ↓
flake.nix → modules/*.nix (uses vars)
```

## Key Benefits

✅ **Nix-native**: Uses built-in `builtins.fromJSON` (no custom parser)
✅ **Type-safe**: Real booleans, numbers, arrays, objects
✅ **Hierarchical**: Natural nested structure
✅ **Git-safe**: `config.json` is automatically ignored by git
✅ **Flexible**: All .nix files can be updated freely without conflicts
✅ **Simple**: Clean JSON format with validation tools available

## Configuration Options

### Example config.json

```json
{
  "hostname": "xoa",
  "username": "admin",
  "timezone": "UTC",
  "sshKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... user@laptop"
  ],
  "xo": {
    "host": "0.0.0.0",
    "port": 80,
    "httpsPort": 443,
    "enableV6Preview": false
  },
  "tls": {
    "enable": true,
    "redirectToHttps": true
  },
  "networking": {
    "firewall": {
      "allowedTCPPorts": [80, 443, 3389, 5900, 8012]
    }
  },
  "storage": {
    "nfs": { "enable": true },
    "cifs": { "enable": true },
    "mountsDir": "/var/lib/xo/mounts"
  },
  "updates": {
    "gc": {
      "enable": true,
      "schedule": "Sun 04:00",
      "keepGenerations": 7
    }
  }
}
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

```json
{
  "sshKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... alice@laptop",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcd... bob@desktop",
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... charlie@phone"
  ]
}
```

You can add comments by using keys starting with `_comment` or `_example` (they'll be filtered out):

```json
{
  "sshKeys": [
    "_comment: Add your SSH public keys here",
    "ssh-ed25519 AAAAC3... your-key-here"
  ]
}
```

### Web Interface Settings

```json
{
  "xo": {
    "host": "0.0.0.0",        // 0.0.0.0 = all interfaces, 127.0.0.1 = localhost only
    "port": 80,               // HTTP port
    "httpsPort": 443,         // HTTPS port
    "enableV6Preview": false  // Enable XO v6 preview at /v6
  },
  "tls": {
    "enable": true,              // Auto-generate self-signed certificates
    "redirectToHttps": true,     // Redirect HTTP to HTTPS
    "dir": "/etc/ssl/xo",        // Certificate directory
    "cert": "/etc/ssl/xo/certificate.pem",
    "key": "/etc/ssl/xo/key.pem"
  }
}
```

### Firewall

```json
{
  "networking": {
    "firewall": {
      "allowedTCPPorts": [
        80,    // HTTP
        443,   // HTTPS
        3389,  // RDP console
        5900,  // VNC console
        8012   // XO service port
      ]
    }
  }
}
```

### Storage

```json
{
  "storage": {
    "nfs": {
      "enable": true    // Enable NFS remote storage
    },
    "cifs": {
      "enable": true    // Enable CIFS/SMB remote storage
    },
    "mountsDir": "/var/lib/xo/mounts"
  }
}
```

### Automated Updates

Configure automatic updates for different components:

**Garbage Collection:**
```json
{
  "updates": {
    "gc": {
      "enable": true,
      "schedule": "Sun 04:00",
      "keepGenerations": 7
    }
  }
}
```

**Flake Self-Update:**
```json
{
  "updates": {
    "flake": {
      "enable": true,
      "schedule": "Sun 04:00",
      "remoteUrl": "https://codeberg.org/dalemorgan/declarative-xoa-ce.git",
      "branch": "main",
      "autoRebuild": false
    }
  }
}
```

**Component Updates:**
```json
{
  "updates": {
    "nixpkgs": {
      "enable": true,
      "schedule": "Mon 04:00",
      "keepGenerations": 7
    },
    "xoa": {
      "enable": true,
      "schedule": "Tue 04:00",
      "keepGenerations": 7
    },
    "libvhdi": {
      "enable": true,
      "schedule": "Wed 04:00",
      "keepGenerations": 7
    }
  }
}
```

### Notifications

**Email:**
```json
{
  "updates": {
    "monitoring": {
      "notifyOnSuccess": false,
      "email": {
        "enable": true,
        "to": "admin@example.com"
      }
    }
  }
}
```

**ntfy.sh Push Notifications:**
```json
{
  "updates": {
    "monitoring": {
      "ntfy": {
        "enable": true,
        "server": "https://ntfy.sh",
        "topic": "my-unique-topic-name"
      }
    }
  }
}
```

**Webhook:**
```json
{
  "updates": {
    "monitoring": {
      "webhook": {
        "enable": true,
        "url": "https://hooks.example.com/webhook"
      }
    }
  }
}
```

### Terminal Enhancements

```json
{
  "extras": {
    "enable": false  // Enable enhanced terminal (zsh, oh-my-posh, fzf, etc.)
  }
}
```

### Service Account

```json
{
  "service": {
    "xoUser": "xo",    // Rarely needs changing
    "xoGroup": "xo"
  }
}
```

### State Version

```json
{
  "stateVersion": "25.05"  // DO NOT CHANGE after initial installation
}
```

## JSON Tips

### Validation

Validate your JSON before rebuilding:

```bash
# Check if JSON is valid
jq . config.json

# Pretty-print
jq . config.json > config.tmp && mv config.tmp config.json

# Check specific value
jq '.hostname' config.json
```

### Comments

JSON doesn't support standard comments, but you can use keys starting with `_`:

```json
{
  "_comment": "This is a comment",
  "hostname": "xoa",
  "_note_about_ports": "Ports below 1024 require root",
  "xo": {
    "port": 80
  }
}
```

Keys starting with `_comment` or `_example` in the `sshKeys` array are automatically filtered out.

### Default Values

If you omit a setting from `config.json`, the default value from `config.sample.json` is used. You only need to specify settings you want to change.

**Minimal config.json:**
```json
{
  "hostname": "my-xoa",
  "username": "admin",
  "timezone": "America/New_York",
  "sshKeys": [
    "ssh-ed25519 AAAAC3... user@host"
  ]
}
```

All other settings will use defaults!

## Updating the Flake

With this configuration system, you can safely update the flake without losing your settings:

```bash
# Pull latest changes from upstream
cd ~/nixoa
git pull origin main

# Your config.json is never touched by git
# No merge conflicts!

# Rebuild with your existing configuration
sudo nixos-rebuild switch --flake .#$(hostname)
```

## Troubleshooting

### Configuration not taking effect

Make sure your `config.json`:
- Is in the flake root directory (same directory as `flake.nix`)
- Is valid JSON (use `jq . config.json` to validate)
- Uses proper types (booleans are `true`/`false`, not `"true"`/`"false"`)
- Has no trailing commas (JSON doesn't allow them)

### JSON syntax errors

Common JSON issues:
- ❌ Trailing comma: `{"a": 1,}`
- ✅ No trailing comma: `{"a": 1}`
- ❌ Single quotes: `{'a': 'b'}`
- ✅ Double quotes: `{"a": "b"}`
- ❌ Comments: `{"a": 1 // comment}`
- ✅ Comment keys: `{"_comment": "...", "a": 1}`

Use `jq` to validate:
```bash
jq . config.json || echo "Invalid JSON!"
```

### SSH keys not working

Ensure:
- Keys are in an array: `["key1", "key2"]`
- Keys start with `ssh-ed25519`, `ssh-rsa`, etc.
- Keys are strings with double quotes
- No extra spaces or newlines within the key string

### Checking current configuration

Verify vars.nix is reading your config.json correctly:

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

- `config.json` contains sensitive information (SSH keys, API tokens, etc.)
- Never commit `config.json` to git (it's in `.gitignore`)
- Keep backups of `config.json` in a secure location
- Set appropriate file permissions: `chmod 600 config.json`
- Use SSH keys, not passwords
- Review `config.sample.json` to understand all options

## Support

For issues or questions:
- Check `config.sample.json` for all available options
- Review `vars.nix` to see how defaults are handled
- Validate JSON with `jq . config.json`
- See main README.md for general flake documentation
