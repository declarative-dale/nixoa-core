# NiXOA Core

NiXOA core is the **immutable appliance library** for NiXOA. It exports curated
NixOS module stacks, overlays, and packages for Xen Orchestra CE hosts while
leaving host policy to the separate `system/` flake.

## What Core Provides

- `nixosModules.platform`
- `nixosModules.virtualization`
- `nixosModules.xo`
- `nixosModules.xenOrchestra`
- `nixosModules.appliance`
- `overlays.nixoa`
- `packages.x86_64-linux.{xen-orchestra-ce,libvhdi,metadata}`

## Repository Shape

```text
core/
├── docs/
├── lib/
├── modules/
│   ├── dendritic.nix
│   ├── outputs/
│   │   ├── nixos-modules.nix
│   │   ├── overlays.nix
│   │   └── packages.nix
│   └── _nixos/
│       └── features/
│           ├── foundation/
│           ├── platform/
│           ├── virtualization/
│           └── xo/
├── scripts/
│   ├── migrate-redis-to-valkey.sh
│   ├── xoa-logs.sh
│   └── xoa-update.sh
├── flake.lock
└── flake.nix
```

## Design Notes

- Core does not own host bootstrap or installation scripts. Those now belong in `system/`.
- Core does not export a `denful` namespace. It publishes curated flake outputs instead because the current system/core relationship does not need cross-flake aspect exchange.
- User-editable values like hostname, username, SSH keys, and firewall policy belong in `system/config/`.

## Example

```nix
{
  inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";

  outputs = { nixoaCore, nixpkgs, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      modules = [
        nixoaCore.nixosModules.platform
        nixoaCore.nixosModules.virtualization
        nixoaCore.nixosModules.xenOrchestra
      ];
    };
  };
}
```

## Notes

- `nixosModules.appliance` remains the default full stack.
- `system/` is the recommended entrypoint for actual NiXOA hosts.
