# Getting Started

NiXOA is now used directly from the unified `core` repo.

## Bootstrap A Host

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
nix run .#nxcli -- host add
```

The `nxcli host add` flow prompts for hostname, username, timezone, state
version, SSH keys, and deployment profile. It then:

- copies `host/_template/` to `host/<hostname>/`
- writes host-local settings into `host/<hostname>/_ctx/settings.nix`
- copies `hardware-configuration.nix` into `host/<hostname>/_nixos/`
- updates `host/_automation/default.nix` so `nixosConfigurations.vm` targets the selected host VM
- stages the tracked `host/` files so flake evaluation sees the new host
- validates the flake
- optionally performs the first switch through `nh`

Use `scripts/bootstrap.sh` only when you want the older convenience wrapper that
also clones or refreshes a checkout before handing off to `nxcli host add`.

## Operate A Host

From the repo root:

```bash
nxcli status
nxcli apply --target nixo-ce
nxcli apply --target vm --dry-run
nxcli boot --target vm
```

`--target vm` always resolves through `host/_automation/default.nix`, so it is
the stable automation target for VM/XO workflows. Use concrete host names when
you need to pin an operation to one specific host output.

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
