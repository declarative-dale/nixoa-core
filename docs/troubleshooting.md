# Troubleshooting (Core)

Most runtime issues are resolved in the downstream `system/` repository.

## XO Not Starting

Check:

- `enableXO = true` in `config/features.nix`
- XO runtime and TLS settings in `config/xo.nix`

Then inspect:

```bash
systemctl status xo-server
journalctl -u xo-server -n 200
```

## SSH Access Missing

Ensure `sshKeys` is populated in `config/site.nix` or `config/overrides.nix`.

## Firewall Ports Blocked

Update `config/platform.nix` in the host repository.
