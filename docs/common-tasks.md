# Common Tasks (Core Consumers)

These examples are applied in the **system** repo (host config) and consumed by
core modules via `vars`.

## Enable XO

Edit `config/features.nix`:

```nix
{ enableXO = true; }
```

## Enable storage backends

Edit `config/storage.nix`:

```nix
{
  enableNFS = true;
  enableCIFS = true;
  enableVHD = true;
}
```

## Configure XO TLS

Edit `config/xo.nix`:

```nix
{
  enableTLS = true;
  enableAutoCert = true;
}
```

## Open firewall ports

Edit `config/networking.nix`:

```nix
{ allowedTCPPorts = [ 80 443 ]; }
```

## Switch boot loader

Edit `config/boot.nix`:

```nix
{ bootLoader = "grub"; }
```

## Add system packages

Edit `config/packages.nix`:

```nix
{ pkgs, ... }:
{
  systemPackages = with pkgs; [ htop git ];
}
```
