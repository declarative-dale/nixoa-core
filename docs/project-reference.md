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
- `xen-orchestra-supply-protector`
- `libvhdi`
- `nxcli`
- `nixoa-menu`
- `deploy-template`
- `devenv`
- `installer-iso`
- `metadata`
- `sbomnix`

The flake also exposes operator apps for `nxcli`, `apply`, `bootstrap`,
`deploy-template`, `commit`, `diff`, `history`, and `menu`.

Run `nix flake show` for the complete evaluated output tree.

Native devenv and the default `devShells.x86_64-linux` output share the
repository toolchain module. Use `devenv shell` for interactive work and
`devenv tasks run ci:repository-audit` for the complete repository contract.
Exact commands and the compatible flake interfaces are in the
[development guide](development.md).

Pure CI target contracts are exported as
`lib.ciPlans.x86_64-linux.validation` and
`lib.ciPlans.x86_64-linux.installer`. Both use the reusable planner and
Nix-wrapped validator from the locked Xen Orchestra flake; publication,
attestation, and signing remain separate delivery operations.

## Installer delivery

GitHub Actions builds the complete system, public packages, and a
closure-preseeded installer ISO. The ISO is retained as the `nixoa-installer`
artifact from the consolidated `CI` workflow. Every Nix-producing CI job reads
from the public NiXOA Cachix cache and, on trusted repository events, streams
new outputs back through Cachix's daemon. Cachix carries Nix store paths
between jobs and runs; fork pull requests consume the public cache read-only.

The Cachix token and cache name are declared in `secretspec.toml`. GitHub
Actions maps the repository secret and variable through Secretspec once per
job, then shares the masked environment with later actions. The flake packages
Secretspec and validates both the public-read and publishing profiles.

The build uses the flake-provided `sbomnix` to create validated, checksummed
SPDX and CycloneDX runtime inventories for the complete appliance closure.
Cachix substitutes the system closure, SBOM tooling, and xo-nixpkg's matching
`supply-protector-latest` output. Before attestation, the builder verifies that
the upstream assertion names the exact selected XO store path and Cachix trust
root, verifies its checksums and retained Nix reference, and adds a checksummed
SPDX `DESCRIBED_BY` external-document link to the appliance inventory. The
upstream assertion and its SPDX and CycloneDX documents are preserved with the
installer evidence. The finished SBOMs are cached with the ISO and immutable
state in the same 90-day GitHub artifact, so
later runs and releases retrieve the exact tested bundle without regenerating
it. CI boots the ISO with QEMU, signs its build provenance, and binds the SPDX
document to the installer. GitHub release assets carry the tested installer in
numbered parts below GitHub's 2 GiB per-asset limit, plus its whole-file
checksum, both SBOMs, and a checksummed manifest.
Reassemble a directly downloaded installer with `cat nixoa-v*.iso.part-* >
nixoa-v*.iso`, then verify the matching `.iso.sha256` file. The default
`deploy-template` path performs artifact retrieval and verification itself.

Before allocating the installer runner, the route job fingerprints only the
tracked files that affect the appliance, installer, and SBOM outputs. It emits
one versioned JSON plan containing classification, reuse, build, and
protected-main publication decisions. Every downstream job and the required
verdict consume that exact plan. If the input state matches a successful
unexpired build, CI publishes a tiny state pointer to the original immutable
artifact instead of rebuilding it. A fixture test proves that appliance and
artifact-recipe changes alter the fingerprint while version, docs, tests,
non-CI workflow maintenance, and Packer-only changes do not. Unknown tracked
paths are included by default, and the CI workflow is an explicit override to
the ignored GitHub metadata pattern. A relevant up-to-date
pull-request candidate is built and booted once; the resulting state can then
be reused by the identical `main` tree. Pull requests and pushes fetch full
history for this comparison, while schedules and manual runs keep the shallow
checkout. Merge-group inputs are supported defensively for a future repository
transfer but are not triggered in this personal repository; missing,
unavailable, or non-ancestral SHAs require installer validation. The router
and required verdict share a strict schema-v1 JSON route contract.

At deployment time, `deploy-template` downloads the newest successful `main`
artifact to a temporary directory, verifies its SHA-256 checksum and state
pointer, and gives it to Packer. The source flake remains pinned independently
through `flake.lock`.

This means the default installer may briefly lag a newer checkout while CI is
running. Use `INSTALLER_SOURCE=build` for the current checkout or
`INSTALLER_ISO=/path/to/image.iso` for an exact image.

The Determinate, NiXOA, and Xen Orchestra binary caches and their public keys
are declared in `flake.nix`; libvhdi is supplied by the Xen Orchestra closure.
Credential-bearing configuration is kept in the runtime Secretspec contract.

## Automation

- Pull requests run flake, source, workflow, lock-health, ShellCheck,
  actionlint, and `zizmor` checks. The stable `Required CI verdict` summarizes the
  conditional graph for branch protection.
- Relevant pull requests build and boot the installer. The protected branch
  must be current before auto-merge, then `main` reuses the identical immutable
  artifact while metadata-only changes skip planning.
- A forced build and boot runs every other month so runtime and cache drift are
  detected before the 90-day artifact expires.
- A scheduled workflow refreshes `devenv.lock` and `flake.lock` every Wednesday
  at 09:17 UTC, verifies their shared pins, and opens or updates one pull
  request.
- Weekly grouped Dependabot updates carry a seven-day cooldown. A narrow bot
  verifies the exact trusted author, repository, branch, title, and head SHA,
  waits for that SHA's CI, and only then enables protected-branch auto-merge.
- Successful installer builds publish the `0.2` rolling FlakeHub release. The
  dedicated release workflow selects a semantic version through a protected
  pull request, verifies both builder attestations, fills a draft GitHub
  release, publishes the versioned flake, and makes the GitHub release
  immutable. Rolling and versioned publication wait in the same non-canceling
  queue so they do not build identical outputs concurrently. The next
  development version passes through the same protection.
- Release, development-version, and flake-input pull requests use the
  repository-scoped `GITHUB_TOKEN`. Trusted automation dispatches CI for the
  exact head SHA, waits for the protected `Required CI verdict`, and enables auto-merge
  after validating the bot identity, branch, title, repository, and allowlisted
  files. Version pull requests carry exactly the `VERSION` change.
- `VERSION` records the current development release. The release workflow
  changes it to the selected stable version and advances it to the next patch
  development version after publication.

See the [Packer reference](../packer/README.md) for the installer build and
template-sealing contract.

[Back to documentation](index.md)
