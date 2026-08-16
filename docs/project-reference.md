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
- `sbomnix`

The flake also exposes operator apps for `nxcli`, `apply`, `bootstrap`,
`deploy-template`, `commit`, `diff`, `history`, and `menu`.

Run `nix flake show` for the complete evaluated output tree.

## Installer delivery

GitHub Actions builds the complete system, public packages, and a
closure-preseeded installer ISO. The ISO is retained as the `nixoa-installer`
workflow artifact; smaller reusable package closures are published to Cachix.
Determinate Magic Nix Cache reuses CI-only build results through GitHub's
free native cache without replacing the public Cachix publishing path. CI
explicitly disables the separate FlakeHub Cache service.

The build also uses `sbomnix` to create SPDX and CycloneDX runtime SBOMs for
the complete appliance closure. The tested installer, both SBOMs, their
checksums, and a release manifest become immutable GitHub release assets.

Before allocating a Nix runner, a small planning job fingerprints only the
tracked files that affect the appliance, installer, and SBOM outputs. If that
input state matches a successful unexpired build, CI publishes a tiny state
pointer to the original immutable artifact instead of rebuilding it. A fixture
test proves that appliance changes alter the fingerprint while version, docs,
tests, workflow maintenance, and Packer-only changes do not. Artifact recipe
changes deliberately update the fingerprint script's state schema.

The installer artifact is not a flake input and does not appear in
`flake.lock`. At deployment time, `deploy-template` downloads the newest
successful `main` artifact to a temporary directory, verifies its SHA-256
checksum and state pointer, and gives it to Packer.

This means the default installer may briefly lag a newer checkout while CI is
running. Use `INSTALLER_SOURCE=build` for the current checkout or
`INSTALLER_ISO=/path/to/image.iso` for an exact image.

The Determinate, NiXOA, Xen Orchestra, and libvhdi binary caches and their
public keys are declared in `flake.nix`.

## Automation

- Pull requests, merge-queue candidates, and `main` run the lightweight flake,
  source, workflow, and lock-health validation lane.
- Installer CI fingerprints appliance code and locked inputs, then reuses a
  matching immutable artifact for metadata-only commits. Documentation-only
  changes do not start even the planning workflow.
- A scheduled workflow refreshes all locked inputs every Wednesday at 09:17
  UTC and opens or updates a pull request.
- Weekly grouped Dependabot updates carry a seven-day cooldown. A narrow bot
  may enable auto-merge only for Dependabot or the known flake refresh branch;
  required validation and merge-queue policy still decide when they merge.
- Successful installer builds publish the `0.2` rolling FlakeHub release; a
  late publication failure does not invalidate an already verified artifact. The
  dedicated release workflow selects a semantic version, verifies a tested
  artifact inventory, fills a draft GitHub release, publishes the versioned
  flake, and only then makes the release immutable.
- `VERSION` records the current development release. The release workflow
  changes it to the selected stable version and advances it to the next patch
  development version after publication.

See the [Packer reference](../packer/README.md) for the installer build and
template-sealing contract.

[Back to documentation](index.md)
