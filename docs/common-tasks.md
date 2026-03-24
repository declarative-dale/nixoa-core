# Common Tasks (Core Consumers)

These edits happen in the downstream `system/` repo and are consumed by core.

## Enable XO

Edit `config/features.nix`:

```nix
{ enableXO = true; }
```

## Configure TLS

Edit `config/xo.nix`:

```nix
{
  enableTLS = true;
  enableAutoCert = true;
}
```

## Open Firewall Ports

Edit `config/platform.nix`:

```nix
{ allowedTCPPorts = [ 80 443 ]; }
```

## Switch Boot Loader

Edit `config/platform.nix`:

```nix
{ bootLoader = "grub"; }
```
