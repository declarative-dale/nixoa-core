# Troubleshooting

## XO Not Starting

Check the active host's `host/<hostname>/_ctx/settings.nix` for:

- `enableXO = true`
- correct XO runtime and TLS settings

Then inspect:

```bash
systemctl status xo-server
journalctl -u xo-server -n 200
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
