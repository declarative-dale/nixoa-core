# Installation

NiXOA is installed directly from this repo.

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
