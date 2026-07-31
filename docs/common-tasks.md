# Common Tasks

## Add an SSH key

Use `nixoa-menu`, or edit `nixoa.operator.sshKeys` in
`host/settings.nix`, then run:

```bash
nxcli apply
```

## Add packages

Durable packages belong in `nixoa.operator.systemPackages` or
`nixoa.operator.userPackages` in `host/settings.nix`. Values are nixpkgs
attribute paths such as `"ripgrep"` or `"python313Packages.httpx"`.

Console-added packages are written to `host/menu.nix`.

## Toggle development mode

```bash
nxcli host development-mode toggle
nxcli apply
```

## Use a supplied TLS certificate

Place the certificate and key outside the Nix store, set
`nixoa.xo.tls.cert` and `key` to those runtime paths, and set:

```nix
nixoa.xo.tls.autoCert = false;
```

Ensure the `xo` user can read the files.

## Change XO storage support

```nix
nixoa.xo.storage = {
  enableNFS = true;
  enableCIFS = false;
  enableVHD = true;
};
```

Disabled protocols are rejected by the privileged helper.

## Queue a menu rebuild

After a TUI change, choose “Queue rebuild for next boot.” This writes
`/var/lib/nixoa/rebuild-on-boot.env`; `nixoa-rebuild.service` consumes it once
on the next boot.
