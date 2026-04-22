# Troubleshooting

## XO Not Starting

Check the active host's `hosts/<hostname>/_ctx/settings.nix` for:

- `enableXO = true`
- correct XO runtime and TLS settings

Then inspect:

```bash
systemctl status xo-server
journalctl -u xo-server -n 200
```

## SSH Access Missing

Ensure `sshKeys` is populated in `hosts/<hostname>/_ctx/settings.nix`.

## Firewall Ports Blocked

Update `allowedTCPPorts` or `allowedUDPPorts` in `hosts/<hostname>/_ctx/settings.nix`
and re-apply the host.

## New Host Does Not Resolve In The Flake

Ensure the host directory exists at `hosts/<hostname>/` and includes
`default.nix`. If the repo is still in a git worktree evaluation path, stage
the new directory with:

```bash
git add hosts/<hostname>
```
