# Common Tasks

Put durable changes in `host/settings.nix`, then use the same safe workflow:

```bash
nxcli diff
nxcli apply --dry-run
nxcli apply
```

You can also make supported changes through `nixoa-menu`. The console stores
its overrides separately in `host/menu.nix`.

## Add an SSH key

Add the complete public key to `nixoa.operator.sshKeys`:

```nix
nixoa.operator.sshKeys = [
  "ssh-ed25519 AAAA... operator@example"
];
```

Keep at least one known-good key until you have tested the new one in a second
SSH session.

## Add packages

Use nixpkgs attribute paths as strings:

```nix
nixoa.operator = {
  systemPackages = ["ripgrep"];
  userPackages = ["python313Packages.httpx"];
};
```

System packages are available to the whole appliance. User packages belong to
the `nixoa` operator.

## Enable development tools

```bash
nxcli host development-mode on
nxcli apply
```

Disable them again with `nxcli host development-mode off`.

## Use your own TLS certificate

Store the certificate and key outside the Nix store, then point NiXOA to their
runtime paths:

```nix
nixoa.xo.tls = {
  autoCert = false;
  cert = "/run/credentials/xo/certificate.pem";
  key = "/run/credentials/xo/private-key.pem";
};
```

The `xo` service user must be able to read both files. Never place a private
key directly in a Nix file; that would copy it into the world-readable Nix
store.

## Change storage support

```nix
nixoa.xo.storage = {
  enableNFS = true;
  enableCIFS = false;
  enableVHD = true;
};
```

The privileged storage helper rejects disabled protocols.

## Queue a rebuild for next boot

In `nixoa-menu`, choose **Queue rebuild for next boot**. The request is consumed
once during the next boot.

[Back to documentation](index.md)
