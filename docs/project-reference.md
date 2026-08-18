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
- `devenv`
- `installer-iso`
- `metadata`
- `sbomnix`

The flake also exposes operator apps for `nxcli`, `apply`, `bootstrap`,
`deploy-template`, `commit`, `diff`, `history`, and `menu`.

Run `nix flake show` for the complete evaluated output tree.

Native devenv and the default `devShells.x86_64-linux` output share the
repository toolchain module. Use `devenv shell` and `devenv tasks run ci:check`
for normal work; `nix develop` remains the flake-only fallback. Exact commands
are in the [development guide](development.md).

## Installer delivery

GitHub Actions builds the complete system, public packages, and a
closure-preseeded installer ISO. The ISO is retained as the `nixoa-installer`
artifact from the consolidated `CI` workflow. Every Nix-producing CI job reads
from the public NiXOA Cachix cache and, on trusted repository events, streams
new outputs back through Cachix's daemon. GitHub's cache separately restores
only devenv evaluation and task metadata; it never transports Nix store paths,
runtime state, garbage-collection roots, or secrets. Later jobs therefore
reuse the same store paths without a temporary NAR artifact.
Fork pull requests remain read-only when the publishing token is unavailable.

The Cachix token and cache name are declared in `secretspec.toml`. GitHub
Actions maps the repository secret and variable into the official Secretspec
action once per job; subsequent actions consume only the masked, exported
environment. The flake packages Secretspec and validates both the token-free
and publishing profiles without resolving values into the Nix store.

The build uses the flake-provided `sbomnix` to create validated, checksummed
SPDX and CycloneDX runtime inventories for the complete appliance closure.
Cachix substitutes the system closure and SBOM tooling. The finished SBOMs are
cached with the ISO and immutable state in the same 90-day GitHub artifact, so
later runs and releases retrieve the exact tested bundle without regenerating
it. CI boots the ISO with QEMU, signs its build provenance, and binds the SPDX
document to the installer. GitHub release assets carry the tested installer in
numbered parts below GitHub's 2 GiB per-asset limit, plus its whole-file
checksum, both SBOMs, and a checksummed manifest.
Reassemble a directly downloaded installer with `cat nixoa-v*.iso.part-* >
nixoa-v*.iso`, then verify the matching `.iso.sha256` file. The default
`deploy-template` path performs artifact retrieval and verification itself.

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
public keys are declared in `flake.nix`; credential-bearing configuration is
kept in the runtime Secretspec contract.

## Automation

- Pull requests run the flake, source, workflow, lock-health, ShellCheck,
  actionlint, and `zizmor` checks. The stable `CI gate` is the only required
  status context.
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
- Successful installer builds publish the `0.2` rolling FlakeHub release; a
  late publication failure does not invalidate an already verified artifact. The
  dedicated release workflow selects a semantic version through a protected
  pull request, verifies both builder attestations, fills a draft GitHub
  release, publishes the versioned flake, and only then makes the release
  immutable. The next development version also passes through the queue.
- Release, development-version, and flake-input pull requests use only the
  repository-scoped `GITHUB_TOKEN`. Because its pull requests do not emit a new
  pull-request workflow event, trusted automation dispatches CI for the exact
  head SHA, waits for the protected `CI gate`, and then enables auto-merge.
  Scheduled recovery accepts only exact bot identities, branch/title shapes,
  and allowlisted file changes; version pull requests may change only `VERSION`.
- `VERSION` records the current development release. The release workflow
  changes it to the selected stable version and advances it to the next patch
  development version after publication.

See the [Packer reference](../packer/README.md) for the installer build and
template-sealing contract.

[Back to documentation](index.md)
