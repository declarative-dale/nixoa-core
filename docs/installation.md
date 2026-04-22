# Installation

NiXOA is installed directly from this repo.

## Fresh Base Install Prep

On a fresh NixOS install, run this once as the `nixos` user before bootstrap so
the XO Cachix cache and first-install keys are trusted by the daemon:

```bash
sudo install -d -m 0755 /etc/nix
sudo grep -q 'trusted-users = .*nixos' /etc/nix/nix.conf 2>/dev/null \
  || echo 'trusted-users = root nixos @wheel' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'install.determinate.systems' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-substituters = https://install.determinate.systems https://xen-orchestra-ce.cachix.org' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E=' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-trusted-public-keys = cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM= xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E=' | sudo tee -a /etc/nix/nix.conf >/dev/null
```

## Bootstrap Install

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
nix run .#nxcli -- host add --first-switch
```

`nxcli host add` creates a concrete host directory under `host/<hostname>/`,
writes the selected values into Den-shaped host files, updates
`host/_automation/default.nix` so `nixosConfigurations.vm` targets that host's
VM output, validates the flake, and runs the first switch through `nh` when
`--first-switch` is used. `scripts/bootstrap.sh` remains available as a
checkout/bootstrap wrapper around the same flow.

## Manual Install

1. Prefer `nxcli host add <hostname>` from the repo root.
2. Review `host/<hostname>/_ctx/settings.nix`.
3. Confirm `host/_automation/default.nix` points `vmHost` at the intended host when you plan to use the stable `vm` target.
4. Validate with `nix flake check --no-write-lock-file`.
5. Before the first apply, run `./scripts/nxcli.sh apply --target <hostname>` from the repo checkout.
6. Use `./scripts/nxcli.sh boot --target vm` when you want the safer “activate on next reboot” path for the stable VM target.
7. After the first successful apply, `nxcli` is installed on the host and can be used directly without the repo-local launcher path.

## Reusable Den Import

If another flake wants only the NiXOA aspect namespace, import this repo as a
normal Den source:

```nix
inputs.den.url = "github:denful/den";
inputs.nixoaCore.url = "git+https://codeberg.org/NiXOA/core.git?ref=beta";
```

```nix
imports = [
  inputs.den.flakeModules.dendritic
  (inputs.den.namespace "nixoaCore" [ inputs.nixoaCore ])
];
```

```nix
_module.args.__findFile = den.lib.__findFile;
```
