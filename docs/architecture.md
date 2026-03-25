# Core Architecture

NiXOA core is a reusable appliance library. It keeps plain NixOS feature
modules under `modules/nixos/` and publishes only a small curated output
surface from `modules/outputs/`.

## Repository Shape

```text
modules/
├── dendritic.nix
├── outputs/
│   ├── stacks.nix
│   ├── overlays.nix
│   └── packages.nix
└── nixos/
    └── features/
        ├── shared/
        ├── platform/
        ├── virtualization/
        └── xen-orchestra/
```

## Curated Exports

`modules/outputs/stacks.nix` defines the public module stacks:

- `platform`
- `virtualization`
- `xenOrchestra`
- `appliance`

The overlay and package outputs live in:

- `modules/outputs/overlays.nix`
- `modules/outputs/packages.nix`

## Relationship To System

`system/` imports core as a flake input and applies:

- `nixoaCore.nixosModules.appliance`
- `nixoaCore.overlays.nixoa`

Host policy stays in `system/config/*`, which composes into `vars` and is passed
to core modules through NixOS `specialArgs`.

## Why No Namespace

Den namespaces are useful when a flake is intentionally exporting reusable
aspects to other den flakes through `flake.denful`. Core currently exports
curated NixOS stacks instead, so a namespace would add a custom flake output
without improving the present core/system composition model.
