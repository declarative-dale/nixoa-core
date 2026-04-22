# Getting Started

NiXOA is now used directly from the unified `core` repo.

## Bootstrap A Host

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
./scripts/bootstrap.sh
```

The bootstrap flow prompts for hostname, username, timezone, state version,
SSH keys, repo path, and deployment profile. It then:

- copies `hosts/_template/` to `hosts/<hostname>/`
- writes host-local settings into `hosts/<hostname>/_ctx/settings.nix`
- copies `hardware-configuration.nix` into `hosts/<hostname>/_nixos/`
- stages `hosts/<hostname>/` so flake evaluation sees the new host
- validates the flake
- optionally performs the first switch through `nh`

The suggested hostname during bootstrap is `nixo-ce`. The repo also ships a
sample concrete host at `hosts/nixo-ce-example/`.

## Operate A Host

From the repo root:

```bash
./scripts/show-diff.sh
./scripts/apply-config.sh --hostname nixo-ce
nh os switch .#nixosConfigurations.nixo-ce
```

## Reuse The Namespace Elsewhere

Another Den flake can still import the reusable namespace directly:

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
