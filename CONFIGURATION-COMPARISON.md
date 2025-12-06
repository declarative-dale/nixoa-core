<!-- SPDX-License-Identifier: Apache-2.0 -->
# Configuration Approach: TOML

This flake uses **TOML configuration** for all personal settings. TOML provides the best balance of human readability and Nix-native support.

## Why TOML?

| Feature | TOML (Current) | JSON (Previous) | .env |
|---------|---------------|-----------------|------|
| **Nix-native** | ✅ Uses `builtins.fromTOML` | ✅ Uses `builtins.fromJSON` | ⚠️ Custom parser |
| **Complexity** | ✅ Simple, no lib.nix needed | ✅ Simple, no lib.nix needed | ⚠️ Requires lib.nix |
| **Type Safety** | ✅ Structured data | ✅ Structured data | ⚠️ String-only |
| **Lists** | ✅ Native arrays | ✅ Native arrays | ⚠️ Comma-separated strings |
| **Nested Config** | ✅ Natural hierarchy | ✅ Natural hierarchy | ⚠️ Flat namespace with _ |
| **Readability** | ✅ Very readable | ⚠️ Somewhat verbose | ✅ Simple KEY=value |
| **Comments** | ✅ Native # comments | ⚠️ No standard comments | ✅ Native # comments |
| **Trailing Commas** | ✅ Allowed | ❌ Not allowed | N/A |

## Current Approach: TOML Configuration

### Setup

1. **Create your config:**
   ```bash
   cp sample-nixoa.toml nixoa.toml
   nano nixoa.toml
   ```

2. **Edit your settings in TOML format:**
   ```toml
   hostname = "xoa"
   username = "admin"
   timezone = "America/New_York"

   sshKeys = [
     "ssh-ed25519 AAAAC3... user@host"
   ]

   [xo]
   port = 80
   httpsPort = 443
   ```

### Advantages
- ✅ **Nix-native**: Uses `builtins.fromTOML` (built-in since Nix 2.3)
- ✅ **Simpler code**: No custom parser needed (no lib.nix)
- ✅ **Type-safe**: Proper booleans, numbers, arrays
- ✅ **Structured**: Natural hierarchical configuration with sections
- ✅ **Human-readable**: More readable than JSON
- ✅ **Native comments**: Use `#` for comments
- ✅ **Flexible**: Trailing commas allowed in arrays
- ✅ **Widely used**: Standard format in Rust, Python, and Go ecosystems

### Example

**nixoa.toml:**
```toml
# System configuration
hostname = "my-xoa-server"
timezone = "Europe/London"

# SSH keys for admin access
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbc... alice@laptop",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcd... bob@desktop"
]

[xo]
port = 8080

[networking.firewall]
allowedTCPPorts = [80, 443, 8080, 8443]

[updates.gc]
enable = true
schedule = "Sun 02:00"
```

### Validation

Validate your TOML before rebuilding:
```bash
nix eval --impure --expr 'builtins.fromTOML (builtins.readFile ./nixoa.toml)'
```

---

## Historical Note: .env Configuration (Deprecated)

### Setup

1. **Use the .env-based vars.nix** (legacy):
   ```bash
   cd /etc/nixos/nixoa-ce
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

## Migration from JSON

If you have an existing `config.json` file, migration to TOML is straightforward:

```bash
# The structure is nearly identical, main changes:
# JSON                          →  TOML
# ================================  ================================
# {                                 hostname = "xoa"
#   "hostname": "xoa",
#   "sshKeys": [                    sshKeys = [
#     "ssh-ed25519..."                "ssh-ed25519..."
#   ],                              ]
#   "xo": {
#     "port": 80                    [xo]
#   }                               port = 80
# }

# Create nixoa.toml from your existing config.json
# (manually convert or use an online JSON→TOML converter)

# The vars.nix file has already been updated to use builtins.fromTOML
# Just create nixoa.toml and rebuild:
sudo nixos-rebuild switch --flake .#$(hostname)
```

**Key Conversion Rules:**
- Top-level key-value pairs: `"key": "value"` → `key = "value"`
- Objects become sections: `"xo": { "port": 80 }` → `[xo]` then `port = 80`
- Arrays stay the same: `[80, 443]` → `[80, 443]`
- Nested objects: `"networking": { "firewall": {...} }` → `[networking.firewall]`
- Comments: `"_comment": "..."` → `# ...`

---

## Why TOML Over JSON?

TOML provides all the benefits of JSON while being more human-friendly:
- **Native comments**: No workarounds needed
- **More readable**: Less visual noise (no quotes on keys, no trailing comma issues)
- **Equally powerful**: Same type system (booleans, numbers, strings, arrays, objects)
- **Nix-native**: `builtins.fromTOML` is built-in, just like `builtins.fromJSON`

---

## Help

See **CONFIGURATION.md** for detailed documentation on all available options.
