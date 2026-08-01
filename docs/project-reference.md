# Project Reference

> This page covers repository and release details for contributors and advanced
> users. Most operators can start with [Getting started](getting-started.md).

## Fixed appliance output

The flake defines one NixOS system:

```text
nixosConfigurations.nixoa
```

Its architecture is `x86_64-linux`, its operator is `nixoa`, and every
operator command targets `.#nixoa`.

## Packages and apps

Public packages include:

- `xen-orchestra-ce`
- `libvhdi`
- `nxcli`
- `nixoa-menu`
- `deploy-template`
- `installer-iso`
- `metadata`

The flake also exposes operator apps for `nxcli`, `apply`, `bootstrap`,
`deploy-template`, `commit`, `diff`, `history`, and `menu`.

Run `nix flake show` for the complete evaluated output tree.

## Installer delivery

GitHub Actions builds the complete system, public packages, and a
closure-preseeded installer ISO. The ISO is retained as the `nixoa-installer`
workflow artifact; smaller reusable package closures are published to Cachix.

The installer artifact is not a flake input and does not appear in
`flake.lock`. At deployment time, `deploy-template` downloads the newest
successful `main` artifact to a temporary directory, verifies its SHA-256
checksum, and gives it to Packer.

This means the default installer may briefly lag a newer checkout while CI is
running. Use `INSTALLER_SOURCE=build` for the current checkout or
`INSTALLER_ISO=/path/to/image.iso` for an exact image.

The Determinate, NiXOA, Xen Orchestra, and libvhdi binary caches and their
public keys are declared in `flake.nix`.

## Automation

- Installer CI runs when appliance code or its locked inputs change.
  Documentation-only changes do not rebuild the installer.
- A scheduled workflow refreshes all locked inputs every Wednesday at 09:17
  UTC and opens or updates a pull request.
- Merging that pull request is what applies the new lock file to `main`.
- Non-documentation changes on `main` publish the rolling FlakeHub release;
  version tags publish tagged releases.

See the [Packer reference](../packer/README.md) for the installer build and
template-sealing contract.

[Back to documentation](index.md)
