# Installation

NiXOA is installed directly from this repo.

## Bootstrap Install

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
./scripts/bootstrap.sh --first-switch
```

Bootstrap creates a concrete host directory under `host/<hostname>/`, writes
the selected values into Den-shaped host files, updates
`host/_automation/default.nix` so `nixosConfigurations.vm` targets that host's
VM output, validates the flake, and runs the first switch through `nh` when
`--first-switch` is used.

## Manual Install

1. Copy `host/_template/` to `host/<hostname>/`.
2. Edit `host/<hostname>/_ctx/settings.nix`.
3. Copy your machine's hardware config to `host/<hostname>/_nixos/hardware-configuration.nix`.
4. Set `host/_automation/default.nix` so `vmHost = "<hostname>";`.
5. Stage the tracked host files with `git add host/<hostname> host/_automation/default.nix`.
6. Validate with `nix flake check --no-write-lock-file`.
7. Apply with `nh os switch .#nixosConfigurations.<hostname>`.
8. Build the stable VM alias with `nh os build .#nixosConfigurations.vm`.

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
