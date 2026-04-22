# Configuration Reference

Host-owned configuration now lives inside `hosts/<hostname>/`.

## Host Directory Shape

Each concrete host uses the same Den-shaped layout as the template:

- `default.nix`: declares the concrete Den host and attaches aspects
- `_ctx/settings.nix`: durable host-owned values
- `_ctx/menu.nix`: TUI-managed overrides
- `_nixos/`: host-owned NixOS modules loaded through Den import-tree
- `_homeManager/`: host-owned Home Manager modules loaded through Den import-tree

`hosts/_template/` is only a template. Real machines should use their own
`hosts/<hostname>/` directory.

## Key Host Settings

`_ctx/settings.nix` is the main host-owned context input. Important values include:

- `hostname`
- `username`
- `timezone`
- `stateVersion`
- `sshKeys`
- `deploymentProfile`
- `bootLoader`
- `allowedTCPPorts`
- `allowedUDPPorts`
- `enableXO`
- `enableXenGuest`
- `enableTLS`
- `enableAutoCert`
- `systemPackages`
- `userPackages`
- `enableNFS`
- `enableCIFS`
- `enableVHD`
- `mountsDir`

## Den-Native Split

Reusable defaults stay in exported NiXOA namespaces and aspects. Host-owned
values stay local to `hosts/<hostname>/`.

That means:

- reusable behavior belongs in `modules/nixoaCore/` or supporting modules
- host-local overrides belong in `hosts/<hostname>/`
- `includes` and `provides` handle composition
- host-owned `_nixos` and `_homeManager` trees are imported through `den.provides.import-tree`

XO service identity still defaults inside core through `nixoa.xo.user` and
`nixoa.xo.group`.
