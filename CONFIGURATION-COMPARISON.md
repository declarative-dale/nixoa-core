# Configuration Approaches: .env vs JSON

This flake now supports **two configuration approaches**. Choose the one that fits your workflow best.

## Quick Comparison

| Feature | JSON (Recommended) | .env |
|---------|-------------------|------|
| **Nix-native** | ✅ Uses `builtins.fromJSON` | ⚠️ Custom parser |
| **Complexity** | ✅ Simple, no lib.nix needed | ⚠️ Requires lib.nix |
| **Type Safety** | ✅ Structured data | ⚠️ String-only |
| **Lists** | ✅ Native arrays | ⚠️ Comma-separated strings |
| **Nested Config** | ✅ Natural hierarchy | ⚠️ Flat namespace with _ |
| **Editing** | ⚠️ JSON syntax (strict) | ✅ Simple KEY=value |
| **Tooling** | ✅ Validators, formatters | ⚠️ Basic text editors |
| **Comments** | ⚠️ No standard comments | ✅ Native # comments |

## Recommendation: Use JSON

**JSON is more nix-native and simpler:**
- Uses built-in `builtins.fromJSON` (no custom parsing)
- Proper data types (numbers, booleans, arrays, objects)
- Better structure for complex nested configuration
- JSON validators and formatters available

---

## Option 1: JSON Configuration (Recommended)

### Setup

1. **Use the JSON-based vars.nix:**
   ```bash
   cd ~/nixoa
   mv vars.nix vars-env.nix.backup  # backup the .env version
   mv vars-json.nix vars.nix        # use JSON version
   ```

2. **Create your config:**
   ```bash
   cp config.sample.json config.json
   nano config.json
   ```

3. **Edit your settings in JSON format:**
   ```json
   {
     "hostname": "xoa",
     "username": "admin",
     "timezone": "America/New_York",
     "sshKeys": [
       "ssh-ed25519 AAAAC3... user@host"
     ],
     "xo": {
       "port": 80,
       "httpsPort": 443
     }
   }
   ```

### Pros
- ✅ **Nix-native**: Uses `builtins.fromJSON`
- ✅ **Simpler code**: No custom parser needed (no lib.nix)
- ✅ **Type-safe**: Proper booleans, numbers, arrays
- ✅ **Structured**: Natural hierarchical configuration
- ✅ **Tooling**: JSON validators, formatters (`jq`, `prettier`)
- ✅ **Errors**: JSON syntax errors caught immediately

### Cons
- ⚠️ **Strict syntax**: Must be valid JSON (commas, quotes required)
- ⚠️ **No comments**: JSON doesn't support comments (use `_comment` keys)
- ⚠️ **Less familiar**: Some users prefer simple KEY=value format

### Example

**config.json:**
```json
{
  "hostname": "my-xoa-server",
  "timezone": "Europe/London",
  "sshKeys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... alice@laptop",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcd... bob@desktop"
  ],
  "xo": {
    "port": 8080,
    "enableV6Preview": true
  },
  "networking": {
    "firewall": {
      "allowedTCPPorts": [80, 443, 8080, 8443]
    }
  },
  "updates": {
    "gc": {
      "enable": true,
      "schedule": "Sun 02:00"
    }
  }
}
```

### Validation

Validate your JSON before rebuilding:
```bash
jq . config.json  # Pretty-print and validate
```

---

## Option 2: .env Configuration

### Setup

1. **Use the .env-based vars.nix** (current default):
   ```bash
   cd ~/nixoa
   cp sample.env .env
   nano .env
   ```

2. **Edit your settings:**
   ```bash
   HOSTNAME=xoa
   USERNAME=admin
   TIMEZONE=America/New_York
   SSH_KEY_1=ssh-ed25519 AAAAC3... user@host
   XO_PORT=80
   ```

### Pros
- ✅ **Simple format**: Easy KEY=value syntax
- ✅ **Comments**: Native `#` comments
- ✅ **Familiar**: Common in Docker/Node.js ecosystems
- ✅ **No syntax errors**: More forgiving format

### Cons
- ⚠️ **Custom parser**: Requires lib.nix (190+ lines of custom code)
- ⚠️ **String-only**: Everything is a string, converted later
- ⚠️ **Flat namespace**: No natural hierarchy (use `UPDATES_GC_ENABLE`)
- ⚠️ **Lists**: Comma-separated strings need parsing
- ⚠️ **Less nix-native**: Custom implementation, not using builtins

### Example

**.env:**
```bash
# System Settings
HOSTNAME=my-xoa-server
TIMEZONE=Europe/London

# SSH Keys
SSH_KEY_1=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... alice@laptop
SSH_KEY_2=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcd... bob@desktop

# Web Interface
XO_PORT=8080
ENABLE_V6_PREVIEW=true

# Firewall
FIREWALL_TCP_PORTS=80,443,8080,8443

# Updates
UPDATES_GC_ENABLE=true
UPDATES_GC_SCHEDULE="Sun 02:00"
```

---

## Migration

### From .env to JSON

```bash
# 1. Create config.json from sample
cp config.sample.json config.json

# 2. Manually transfer your settings from .env to config.json
#    Convert:
#      HOSTNAME=xoa              →  "hostname": "xoa"
#      XO_PORT=8080              →  "xo": { "port": 8080 }
#      FIREWALL_TCP_PORTS=80,443 →  "networking": { "firewall": { "allowedTCPPorts": [80, 443] } }

# 3. Switch to JSON vars
mv vars.nix vars-env.nix.backup
mv vars-json.nix vars.nix

# 4. Rebuild
sudo nixos-rebuild switch --flake .#$(hostname)
```

### From JSON to .env

```bash
# 1. Create .env from sample
cp sample.env .env

# 2. Transfer settings from config.json to .env
#    Convert:
#      "hostname": "xoa"                →  HOSTNAME=xoa
#      "xo": { "port": 8080 }           →  XO_PORT=8080
#      "allowedTCPPorts": [80, 443]     →  FIREWALL_TCP_PORTS=80,443

# 3. Switch to .env vars (if you renamed it)
mv vars.nix vars-json.nix.backup
mv vars-env.nix.backup vars.nix

# 4. Rebuild
sudo nixos-rebuild switch --flake .#$(hostname)
```

---

## Recommendation

**For most users: Use JSON**

JSON is more aligned with the Nix ecosystem and provides better structure for complex configuration. The stricter syntax helps catch errors early.

**Use .env only if:**
- You strongly prefer KEY=value format
- You need extensive comments throughout your config
- You're migrating from a Docker-based setup with existing .env files

---

## Both Are Supported

Both approaches are fully functional and supported. The flake will work with either:
- **`vars.nix`** (current) - Uses .env via lib.nix
- **`vars-json.nix`** - Uses config.json via builtins.fromJSON

Simply rename the one you want to `vars.nix` and the flake will use it.

---

## Help

See **CONFIGURATION.md** for detailed documentation on all available options.
