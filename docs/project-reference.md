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

The default `devShells.x86_64-linux` output supplies the repository toolchain.
Use `nix develop` for Rust, Packer, and validation work; the exact commands are
in the [development guide](development.md).

## Installer delivery

GitHub Actions builds the complete system, public packages, and a
closure-preseeded installer ISO. The ISO is retained as the `nixoa-installer`
artifact from the consolidated `CI` workflow; smaller reusable package
closures are published to Cachix.
Determinate Magic Nix Cache reuses results in validation and installer-build
jobs through GitHub's free native cache. The publication job writes its small
reusable closures directly to Cachix and FlakeHub, avoiding a second upload of
the same outputs to GitHub's cache. CI explicitly disables the separate
FlakeHub Cache service.

The build also uses `sbomnix` to create SPDX and CycloneDX runtime SBOMs for
the complete appliance closure. CI boots the ISO with QEMU, signs its build
provenance, and binds the SPDX document to the installer. The tested installer,
both SBOMs, their checksums, and a release manifest become immutable GitHub
release assets.

Before allocating the installer runner, a small planning job fingerprints only the
tracked files that affect the appliance, installer, and SBOM outputs. If that
input state matches a successful unexpired build, CI publishes a tiny state
pointer to the original immutable artifact instead of rebuilding it. A fixture
test proves that appliance and artifact-recipe changes alter the fingerprint
while version, docs, tests, workflow maintenance, and Packer-only changes do
not. A relevant up-to-date pull-request candidate is built and booted once;
the resulting state can then be reused by the identical `main` tree.

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

- Pull requests run the flake, source, workflow, lock-health, ShellCheck,
  actionlint, and `zizmor` checks. The stable `CI gate` is the only required
  status context.
- Relevant pull requests build and boot the installer. The protected branch
  must be current before auto-merge, then `main` reuses the identical immutable
  artifact while metadata-only changes skip planning.
- A forced build and boot runs every other month so runtime and cache drift are
  detected before the 90-day artifact expires.
- A scheduled workflow refreshes all locked inputs every Wednesday at 09:17
  UTC and opens or updates a pull request.
- Weekly grouped Dependabot updates carry a seven-day cooldown. A narrow bot
  verifies the exact trusted author, repository, branch, title, and head SHA,
  waits for that SHA's CI, and only then enables protected-branch auto-merge.
- Successful installer builds publish the `0.2` rolling FlakeHub release; a
  late publication failure does not invalidate an already verified artifact. The
  dedicated release workflow selects a semantic version through a protected
  pull request, verifies both builder attestations, fills a draft GitHub
  release, publishes the versioned flake, and only then makes the release
  immutable. The next development version also passes through the queue.
- `VERSION` records the current development release. The release workflow
  changes it to the selected stable version and advances it to the next patch
  development version after publication.

See the [Packer reference](../packer/README.md) for the installer build and
template-sealing contract.

[Back to documentation](index.md)
