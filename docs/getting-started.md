# Getting Started

NiXOA is now used directly from the unified `core` repo.

## Fresh NixOS Prep

On a fresh machine where you are still operating as the stock `nixos` user, you
can persist the XO cache and first-install substituter settings ahead of time:

```bash
sudo install -d -m 0755 /etc/nix
sudo grep -q 'trusted-users = .*nixos' /etc/nix/nix.conf 2>/dev/null \
  || echo 'trusted-users = root nixos @wheel' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'install.determinate.systems' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-substituters = https://install.determinate.systems https://xen-orchestra-ce.cachix.org' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E=' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-trusted-public-keys = cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM= xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E=' | sudo tee -a /etc/nix/nix.conf >/dev/null
```

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
- optionally performs the first switch through `nixos-rebuild` with the first-install cache options

Use `scripts/bootstrap.sh` only when you want the older convenience wrapper that
also clones or refreshes a checkout before handing off to `nxcli host add`.

## Operate A Host

From the repo root:

```bash
./scripts/nxcli.sh status
./scripts/nxcli.sh apply --target nixo-ce
./scripts/nxcli.sh apply --target vm --dry-run
./scripts/nxcli.sh boot --target vm
```

`--target vm` always resolves through `host/_automation/default.nix`, so it is
the stable automation target for VM/XO workflows. Use concrete host names when
you need to pin an operation to one specific host output.

After the first successful apply, `nxcli` is installed on the host and the same
commands can be run as `nxcli ...` without the repo-local launcher path.

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
