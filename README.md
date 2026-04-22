# NiXOA Core

NiXOA core is the unified Den-native Xen Orchestra appliance flake. It exports
the reusable `flake.denful.nixoa` namespace and also carries concrete host
definitions under `hosts/<hostname>`.

## What It Provides

- `flake.denful.nixoa.platform`
- `flake.denful.nixoa.virtualization`
- `flake.denful.nixoa.xen-orchestra`
- `flake.denful.nixoa.appliance`
- `nixosConfigurations.<hostname>` outputs for concrete hosts under `hosts/`
- host-scoped `nh` apps plus repository apps such as `bootstrap`, `apply`, and `menu`
- `packages.x86_64-linux.{xen-orchestra-ce,libvhdi,nixoa-menu,metadata}`

## Quick Start

Bootstrap a real host from the unified repo:

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
./scripts/bootstrap.sh --first-switch
```

Bootstrap creates `hosts/<hostname>/` by copying `hosts/default/`, writes the
host-local Den-shaped settings there, stages the new host directory so flake
evaluation can see it, validates the flake, and optionally performs the first
switch through `nh`.

You can also operate the repo through flake apps:

```bash
nix run .#bootstrap
nix run .#apply -- --hostname nixo-ce
```

## Layout

```text
core/
├── hosts/
│   ├── default/            # pristine Den-shaped host template
│   └── nixo-ce-example/    # example concrete host
├── modules/
│   ├── dendritic.nix       # installs Den's dendritic flake module
│   ├── namespace.nix       # exports the `nixoa` namespace
│   ├── aspects/            # reusable NiXOA aspect trees
│   ├── hosts/              # imports concrete hosts from hosts/
│   ├── outputs/            # packages, apps, dev shells
│   └── nixos/              # implementation modules behind aspects
├── lib/                    # shared helpers
├── docs/                   # operator-facing docs
├── scripts/                # bootstrap and maintenance helpers
└── flake.nix
```

## Reusable Consumption

NiXOA still works as a reusable Den namespace when another flake wants only the
aspects and not this repo's host tree:

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

## Notes

- `hosts/default/` is a template only and must not be edited in place for a real machine.
- Concrete hosts keep host-owned values locally in `hosts/<hostname>/`.
- `nh` is the primary operator interface for build and switch flows.
- `flake.denful.nixoa` remains the primary reusable public surface.
