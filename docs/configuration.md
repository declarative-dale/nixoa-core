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

- `enableXO`
- `enableXenGuest`
- `xoConfigFile`
- `xoHttpHost`
- `enableTLS`
- `enableAutoCert`
- `enableNFS`
- `enableCIFS`
- `enableVHD`
- `mountsDir`

XO service identity now defaults inside core through `nixoa.xo.user` and
`nixoa.xo.group`, rather than being configured through downstream `vars`.
