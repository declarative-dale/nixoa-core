# NiXOA Core

NiXOA core is the **immutable appliance library** for NiXOA. It exports curated
NixOS module stacks, overlays, and packages for Xen Orchestra CE hosts while
leaving host policy to the separate `system/` flake.

Current release series: `v2.0.0`

## What Core Provides

- `nixosModules.platform`
- `nixosModules.virtualization`
- `nixosModules.xo`
- `nixosModules.xenOrchestra`
- `nixosModules.appliance`
- `overlays.nixoa`
- `packages.x86_64-linux.{xen-orchestra-ce,libvhdi,metadata}`

## Recommended Use

Use `system/` for real hosts. Import `core` directly only when you want the
appliance stacks without the NiXOA host workflow.

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

## Layout

```text
core/
├── modules/
│   ├── outputs/        # public flake surface
│   └── _nixos/         # plain implementation modules
├── lib/                # shared helpers
├── docs/               # consumer-facing docs
├── scripts/            # XO maintenance helpers
└── flake.nix
```

## Notes

- `nixosModules.appliance` remains the default full stack.
- Host bootstrap and install workflow belong in `system/`, not in `core`.
- `denful` is intentionally not exported here; curated flake outputs are the public interface.
- `system/` is the recommended entrypoint for actual NiXOA hosts.
