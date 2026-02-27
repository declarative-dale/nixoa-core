# Troubleshooting (Core)

Issues are typically resolved in the **system** repo configuration.

## XO not starting

Check that `enableXO = true;` is set in `config/features.nix` and review logs:

```bash
systemctl status xo-server
journalctl -u xo-server -n 200
```

## SSH access missing

Ensure `sshKeys` is populated in `config/users.nix` and rebuild.

## Firewall ports blocked

Update `config/networking.nix` to add required TCP/UDP ports.

## TLS issues

Verify `config/xo.nix`:

```nix
{ enableTLS = true; enableAutoCert = true; }
```

Or provide your own certs under `nixoa.xo.tls.*` in a custom module.
