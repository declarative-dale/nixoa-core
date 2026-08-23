# Common Tasks

Put durable changes in `host/settings.nix`, then use the same safe workflow:

```bash
maestroctl diff
maestroctl apply --dry-run
maestroctl apply
```

You can also make supported changes through `maestro-menu`. The console stores
its overrides separately in `host/menu.nix`.

## Add an SSH key

Add the complete public key to `maestro.operator.sshKeys`:

```nix
maestro.operator.sshKeys = [
  "ssh-ed25519 AAAA... operator@example"
];
```

Keep at least one known-good key until you have tested the new one in a second
SSH session.

## Add packages

Use nixpkgs attribute paths as strings:

```nix
maestro.operator = {
  systemPackages = ["ripgrep"];
  userPackages = ["python313Packages.httpx"];
};
```

System packages are available to the whole appliance. User packages belong to
the `maestro` operator.

## Enable development tools

```bash
maestroctl host development-mode on
maestroctl apply
```

Disable them again with `maestroctl host development-mode off`.

## Use your own TLS certificate

Store the certificate and key outside the Nix store, then point Maestro to their
runtime paths:

```nix
maestro.xo.tls = {
  autoCert = false;
  cert = "/run/credentials/xo/certificate.pem";
  key = "/run/credentials/xo/private-key.pem";
};
```

Grant the `xo` service user read access to both runtime files. Keep the private
key in a runtime credential path so it stays outside the Nix store.

## Change storage support

```nix
maestro.xo.storage = {
  enableNFS = true;
  enableCIFS = false;
  enableVHD = true;
};
```

The privileged storage helper permits the protocols enabled here and validates
their mount paths.

## Queue a rebuild for next boot

In `maestro-menu`, choose **Queue rebuild for next boot**. The request is consumed
once during the next boot.

[Back to documentation](index.md)
