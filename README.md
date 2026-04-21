# NiXOA Core

NiXOA core is the **immutable Den-native aspect library** for NiXOA. It exports
a reusable `nixoa` namespace through `flake.denful` and keeps host-specific
policy in the separate `system/` flake.

Current release series: `v3.1.0`

## What Core Provides

- `denful.nixoa.platform`
- `denful.nixoa.virtualization`
- `denful.nixoa.xen-orchestra`
- `denful.nixoa.appliance`
- `packages.x86_64-linux.{xen-orchestra-ce,libvhdi,nixoa-menu,metadata}`

## Recommended Use

Use `system/` for real hosts. Import `core` directly only when you want the
NiXOA aspects without the host-local workflow layered on top.

```nix
{
  inputs.den.url = "github:vic/den";
  inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";

  outputs = inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [
        ({ den, ... }: {
          imports = [
            inputs.den.flakeModules.dendritic
            (inputs.den.namespace "nixoa" [ inputs.nixoaCore ])
          ];

          _module.args.__findFile = den.lib.__findFile;

          den.hosts.x86_64-linux.my-host = { };
          den.aspects.my-host.includes = [ <nixoa/appliance> ];
        })
      ];
    }).config.flake;
}
```

## Layout

```text
core/
├── modules/
│   ├── dendritic.nix   # installs Den's dendritic flake module
│   ├── namespace.nix   # creates and exports the `nixoa` namespace
│   ├── aspects/        # exported NiXOA aspect trees
│   ├── outputs/        # supporting package outputs
│   └── nixos/          # plain implementation modules behind aspects
├── lib/                # shared helpers
├── docs/               # consumer-facing docs
├── scripts/            # XO maintenance helpers
└── flake.nix
```

## Notes

- Host bootstrap and install workflow belong in `system/`, not in `core`.
- XO service identity defaults live in core as `nixoa.xo.user` and `nixoa.xo.group`.
- `flake.denful.nixoa` is the primary public interface.
- `system/` is the recommended entrypoint for actual NiXOA hosts.
