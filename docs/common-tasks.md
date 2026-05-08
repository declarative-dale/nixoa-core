# Common Tasks

These changes are now made directly in `host/<hostname>/_ctx/settings.nix`.
After editing, save the repo change with `nxcli commit` and apply with
`nxcli apply --target <hostname>` or `nxcli apply --target vm`.

## Enable XO

```nix
{ ... }:
{
  enableXO = true;
}
```

## Configure TLS

```nix
{ ... }:
{
  enableTLS = true;
  enableAutoCert = true;
}
```

## Open Firewall Ports

```nix
{ ... }:
{
  allowedTCPPorts = [ 80 443 ];
}
```

## Switch Boot Loader

```nix
{ ... }:
{
  bootLoader = "grub";
}
```

## Add Packages

```nix
{ ... }:
{
  systemPackages = [ "vim" "curl" ];
  userPackages = [ "git" "tmux" ];
}
```
