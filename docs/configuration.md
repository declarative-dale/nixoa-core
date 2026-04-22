# Configuration Reference

Host-owned configuration now lives inside `hosts/<hostname>/`.

## Host Directory Shape

Each concrete host uses the same Den-shaped layout as the template:

- `default.nix`: declares the concrete Den host and attaches aspects
- `context.nix`: merges host-local settings sources
- `settings.nix`: durable host-owned values
- `menu.nix`: TUI-managed overrides
- `host.nix`: final host-owner NixOS imports
- `user.nix`: final user-owner Home Manager imports
- `hardware-configuration.nix`: machine-specific hardware config
- `profiles/vm.nix`: VM profile implementation

`hosts/default/` is only a template. Real machines should use their own
`hosts/<hostname>/` directory.

## Key Host Settings

`settings.nix` is the main host-owned context input. Important values include:

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

- reusable behavior belongs in `modules/aspects/` or supporting modules
- host-local overrides belong in `hosts/<hostname>/`
- `includes` and `provides` handle composition
- `imports` stay limited to the final host-owner and user-owner modules

XO service identity still defaults inside core through `nixoa.xo.user` and
`nixoa.xo.group`.
