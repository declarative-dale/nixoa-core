# Installation

NiXOA is installed directly from this repo.

## Bootstrap Install

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
./scripts/bootstrap.sh --first-switch
```

Bootstrap creates a concrete host directory under `hosts/<hostname>/`, writes
the selected values into Den-shaped host files, validates the flake, and runs
the first switch through `nh` when `--first-switch` is used.

## Manual Install

1. Copy `hosts/_template/` to `hosts/<hostname>/`.
2. Edit `hosts/<hostname>/_ctx/settings.nix`.
3. Copy your machine's hardware config to `hosts/<hostname>/_nixos/hardware-configuration.nix`.
4. Stage the host directory with `git add hosts/<hostname>`.
5. Validate with `nix flake check --no-write-lock-file`.
6. Apply with `nh os switch .#nixosConfigurations.<hostname>`.

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
