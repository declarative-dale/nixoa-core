# Configuration Reference

Host-owned configuration now lives inside `host/<hostname>/`.

## Host Directory Shape

Each concrete host uses the same Den-shaped layout as the template:

- `default.nix`: declares the concrete Den host and attaches aspects
- `_ctx/settings.nix`: durable host-owned values
- `_ctx/menu.nix`: TUI-managed overrides
- `_nixos/`: host-owned NixOS modules loaded through Den import-tree
- `_homeManager/`: host-owned Home Manager modules loaded through Den import-tree

`host/_template/` is only a template. Real machines should use their own
`host/<hostname>/` directory.

`host/_automation/default.nix` keeps the tracked VM-alias selection for the
repo. `nxcli host add` and `nxcli host select-vm` update `vmHost` there so
`nixosConfigurations.vm` resolves to `nixosConfigurations.<hostname>-vm`
without caller-side guessing.

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
- `shell`
- `enableTLS`
- `enableAutoCert`
- `systemPackages`
- `userPackages`
- `flatpaks`
- `flatpakRemotes`
- `extraNixosModules`
- `extraNixosConfig`
- `extraHomeManagerModules`
- `immutability.enable`
- `xoConfig`
- `enableNFS`
- `enableCIFS`
- `enableVHD`
- `mountsDir`

`shell = null` preserves the default behavior: `bash` normally and `zsh` when
`enableExtras = true`. Set `shell = "bash";`, `shell = "zsh";`, or another Den
user-shell name to choose explicitly.

`immutability.enable = false` keeps the operator-friendly mutable mode. When set
to `true`, NixOS manages users declaratively and locks the admin account to
SSH-key access while preserving appliance runtime state.

XO config is declared as literal TOML inside `_ctx/settings.nix`:

```nix
xoConfig.toml = ''
  [redis]
  socket = "/run/redis-xo/redis.sock"

  [http]
  redirectToHttps = true

  [[http.listen]]
  port = 80
'';
```

The string is the complete `/etc/xo-server/config.nixoa.toml` content and is
validated as TOML during builds. This keeps XO configuration declarative while
making edits feel like editing a normal TOML file.

## Den-Native Split

Reusable defaults stay in exported NiXOA namespaces and aspects. Host-owned
values stay local to `host/<hostname>/`.

That means:

- reusable behavior belongs in `modules/nixoaCore/` or supporting modules
- host-local overrides belong in `host/<hostname>/`
- `includes` and `provides` handle composition
- host-owned `_nixos` and `_homeManager` trees are imported through `den._.import-tree`

XO service identity still defaults inside core through `nixoa.xo.user` and
`nixoa.xo.group`.
