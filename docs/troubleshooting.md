# Troubleshooting

Most operational checks use `nxcli`; see the [nxcli reference](nxcli.md) for
full command syntax.

## XO Not Starting

Check the active host's `host/<hostname>/_ctx/settings.nix` for:

- `enableXO = true`
- correct XO runtime and TLS settings

Then inspect:

```bash
sudo systemctl status xo-server.service
nxcli xo logs
```

## SSH Access Missing

Ensure `sshKeys` is populated in `host/<hostname>/_ctx/settings.nix`.

## Firewall Ports Blocked

Update `allowedTCPPorts` or `allowedUDPPorts` in `host/<hostname>/_ctx/settings.nix`
and re-apply the host.

## New Host Does Not Resolve In The Flake

Ensure the host directory exists at `host/<hostname>/` and includes
`default.nix`. If the repo is still in a git worktree evaluation path, stage
the new directory with:

```bash
git add host/<hostname> host/_automation/default.nix
```

## Stable VM Alias Resolves To The Wrong Host

Check `host/_automation/default.nix` and confirm `vmHost` points at the
intended concrete host. The stable alias always resolves to
`nixosConfigurations.<vmHost>-vm`.

To update it through the supported CLI:

```bash
nxcli host select-vm <hostname>
```

## SSH Login Does Not Open The Console

This is the default behavior. Run `nixoa-menu` manually from the shell, or set `nixoaMenuAutoStart = true;` in `host/<hostname>/_ctx/settings.nix` and apply the host if SSH logins should enter the console automatically.

If autostart is enabled but skipped, check that the session is interactive and that `NIXOA_TUI_BYPASS` or `NIXOA_TUI_ACTIVE` is not already set.
