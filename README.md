# NiXOA Core

NiXOA core is the unified Den-native Xen Orchestra appliance flake. It exports
the reusable `flake.denful.nixoaCore` namespace and also carries concrete host
definitions under `hosts/<hostname>`.

## What It Provides

- `flake.denful.nixoaCore.platform`
- `flake.denful.nixoaCore.virtualization`
- `flake.denful.nixoaCore."xen-orchestra"`
- `flake.denful.nixoaCore.appliance`
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

Bootstrap creates `hosts/<hostname>/` by copying `hosts/_template/`, writes the
host-local settings into `_ctx/settings.nix`, stages the new host directory so
flake evaluation can see it, validates the flake, and optionally performs the
first switch through `nh`.

You can also operate the repo through flake apps:

```bash
nix run .#bootstrap
nix run .#apply -- --hostname nixo-ce
```

## Layout

```text
core/
├── hosts/
│   ├── _template/          # pristine Den-shaped host template
│   └── nixo-ce-example/    # example concrete host
├── modules/
│   ├── dendritic.nix       # installs Den's dendritic flake module
│   ├── den-defaults.nix    # keeps Den defaults and routing batteries enabled
│   ├── hosts.nix           # imports concrete hosts from hosts/
│   ├── namespace.nix       # exports the `nixoaCore` namespace
│   ├── nixoaCore/          # reusable exported NiXOA aspects
│   ├── schema.nix          # user schema defaults
│   ├── _nixos/             # shared hidden NixOS implementation trees
│   ├── _homeManager/       # shared hidden Home Manager implementation trees
│   └── outputs/            # packages, apps, dev shells
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
  inputs.den.url = "github:denful/den";
  inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";

  outputs = inputs:
    (inputs.nixpkgs.lib.evalModules {
      modules = [
        ({ den, ... }: {
          imports = [
            inputs.den.flakeModules.dendritic
            (inputs.den.namespace "nixoaCore" [ inputs.nixoaCore ])
          ];

          _module.args.__findFile = den.lib.__findFile;

          den.hosts.x86_64-linux.my-host = { };
          den.aspects.my-host.includes = [ <nixoaCore/appliance> ];
        })
      ];
    }).config.flake;
}
```

## Notes

- Use `<nixoaCore/platform>`, `<nixoaCore/virtualization>`, `<nixoaCore/xen-orchestra>`, and `<nixoaCore/appliance>` as the public aspect paths.
- `hosts/_template/` is a template only and must not be edited in place for a real machine.
- Concrete hosts keep host-owned values locally in `hosts/<hostname>/`.
- `nh` is the primary operator interface for build and switch flows.
- `flake.denful.nixoaCore` remains the primary reusable public surface.
