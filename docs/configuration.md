# Configuration Reference (Core)

Core does not store host policy. It consumes values provided by the downstream
host flake through `vars`.

## Expected Host Configuration Shape

Core is designed around the current `system/` layout:

- `config/site.nix`
- `config/platform.nix`
- `config/features.nix`
- `config/packages.nix`
- `config/xo.nix`
- `config/storage.nix`
- optional `config/overrides.nix`

## Key Vars Consumed By Core

- `hostname`
- `timezone`
- `stateVersion`
- `username`
- `sshKeys`
- `enableExtras`
- `enableXO`
- `enableXenGuest`
- `systemPackages`
- `userPackages`
- `bootLoader`
- `efiCanTouchVariables`
- `grubDevice`
- `allowedTCPPorts`
- `allowedUDPPorts`
- `xoUser`
- `xoGroup`
- `xoConfigFile`
- `xoHttpHost`
- `enableTLS`
- `enableAutoCert`
- `enableNFS`
- `enableCIFS`
- `enableVHD`
- `mountsDir`
- `sudoNoPassword`
