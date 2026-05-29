# Installation

NiXOA is installed directly from this repo.

For a shorter overview, start with the root [README](../README.md). For command details, see the [nxcli reference](nxcli.md).

## Fresh Base Install Prep

On a fresh NixOS install, you can persist the XO and libvhdi Cachix caches and trusted users ahead of time as the `nixos` user. Determinate cache settings are passed only as first-switch command-line options; Determinate Nix manages its own persistent substitution settings after activation.

```bash
sudo install -d -m 0755 /etc/nix
sudo grep -q 'trusted-users = .*nixos' /etc/nix/nix.conf 2>/dev/null \
  || echo 'trusted-users = root nixos @wheel' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'libvhdi-nixpkg.cachix.org' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-substituters = https://xen-orchestra-ce.cachix.org https://libvhdi-nixpkg.cachix.org' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4=' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-trusted-public-keys = xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E= libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4=' | sudo tee -a /etc/nix/nix.conf >/dev/null
```

## Bootstrap Install

```bash
bash <(curl -fsSL https://codeberg.org/NiXOA/core/raw/branch/main/scripts/bootstrap.sh) --enable-flakes
```

If you prefer to clone the repo first:

```bash
git clone https://codeberg.org/NiXOA/core.git ~/nixoa
cd ~/nixoa
nix run .#nxcli -- host add --first-switch
```

`nxcli host add` creates a concrete host directory under `host/<hostname>/`,
writes the selected values into Den-shaped host files, updates
`host/_automation/default.nix` so `nixosConfigurations.vm` targets that host's
VM output, and validates the flake. `scripts/bootstrap.sh` also runs the first
switch through `nixos-rebuild` with first-install cache options by default; pass
`--no-first-switch` to only create the checkout and host files.
`scripts/bootstrap.sh` remains available only for the streamed one-shot
checkout/bootstrap flow; routine host creation and operation should use `nxcli`.

## Manual Install

1. Prefer `nxcli host add <hostname>` from the repo root.
2. Review `host/<hostname>/_ctx/settings.nix`.
3. Confirm `host/_automation/default.nix` points `vmHost` at the intended host when you plan to use the stable `vm` target.
4. Validate with `nix flake check --no-write-lock-file`.
5. Before the first apply, run `nix run .#nxcli -- apply --target <hostname>` from the repo checkout.
6. Use `nix run .#nxcli -- boot --target vm` when you want the safer “activate on next reboot” path for the stable VM target.
7. After the first successful apply, `nxcli` is installed on the host and can be used directly without the repo-local launcher path.
8. Start the operator console manually with `nixoa-menu`, or set `nixoaMenuAutoStart = true;` before applying if SSH logins should enter the console automatically.

## Reusable Den Import

If another flake wants only the NiXOA aspect namespace, import this repo as a normal Den source:

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
