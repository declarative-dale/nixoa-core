# Getting Started

NiXOA is now used directly from the unified `core` repo.

## Fresh NixOS Prep

On a fresh machine where you are still operating as the stock `nixos` user, you can persist the XO and libvhdi Cachix caches and trusted users ahead of time.
Determinate cache settings are passed only as first-switch command-line options; Determinate Nix manages its own persistent substitution settings after activation.

```bash
sudo install -d -m 0755 /etc/nix
sudo grep -q 'trusted-users = .*nixos' /etc/nix/nix.conf 2>/dev/null \
  || echo 'trusted-users = root nixos @wheel' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'libvhdi-nixpkg.cachix.org' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-substituters = https://xen-orchestra-ce.cachix.org https://libvhdi-nixpkg.cachix.org' | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo grep -q 'libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4=' /etc/nix/nix.conf 2>/dev/null \
  || echo 'extra-trusted-public-keys = xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E= libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4=' | sudo tee -a /etc/nix/nix.conf >/dev/null
```

## Bootstrap A Host

```bash
bash <(curl -fsSL https://codeberg.org/NiXOA/core/raw/branch/main/scripts/bootstrap.sh) --enable-flakes
```

If you want a local checkout first, use the canonical `nxcli` app:

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
- performs the first switch through `nixos-rebuild` with the first-install cache options unless `--no-first-switch` is passed to bootstrap

Use `scripts/bootstrap.sh` only for the streamed one-shot install path. Normal
operator work should go through `nix run .#nxcli -- ...` before the first
switch, then `nxcli ...` after the package is installed on the host.

## Operate A Host

From the repo root:

```bash
nix run .#nxcli -- status
nix run .#nxcli -- apply --target nixo-ce
nix run .#nxcli -- apply --target vm --dry-run
nix run .#nxcli -- boot --target vm
```

`--target vm` always resolves through `host/_automation/default.nix`, so it is the stable automation target for VM/XO workflows. Use concrete host names when you need to pin an operation to one specific host output.

After the first successful apply, `nxcli` is installed on the host and the same commands can be run as `nxcli ...` without the repo-local launcher path.

`nixoa-menu` is installed on the host as the SSH operator console. It no longer autostarts on SSH login unless the host context sets
`nixoaMenuAutoStart = true;`; otherwise start it manually with `nixoa-menu`.

For complete command syntax and options, see the
[nxcli reference](nxcli.md).

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
