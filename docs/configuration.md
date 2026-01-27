# Configuration Reference (Core)

Core does **not** hold user configuration. Settings are defined in the
`system/` repo and passed into core modules as `vars`.

## Where to Edit

Use the files under `system/config/`:

```
config/identity.nix
config/users.nix
config/features.nix
config/packages.nix
config/networking.nix
config/xo.nix
config/boot.nix
config/storage.nix
```

## Key Vars Consumed by Core

### Identity
- `hostname`
- `timezone`
- `stateVersion`

### Users
- `username`
- `sshKeys`
- `xoUser`
- `xoGroup`

### Feature Toggles
- `enableXO`
- `enableXenGuest`
- `enableExtras`

### Packages
- `systemPackages`
- `userPackages`

### Networking
- `allowedTCPPorts`
- `allowedUDPPorts`

### XO Settings
- `xoConfigFile`
- `xoHttpHost`
- `enableTLS`
- `enableAutoCert`

### Boot
- `bootLoader`
- `efiCanTouchVariables`
- `grubDevice`

### Storage
- `enableNFS`
- `enableCIFS`
- `enableVHD`
- `mountsDir`
- `sudoNoPassword`

## Example (system/config/identity.nix)

```nix
{
  hostname = "nixoa";
  timezone = "UTC";
  stateVersion = "25.11";
}
```
