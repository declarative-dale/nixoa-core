<!-- SPDX-License-Identifier: Apache-2.0 -->
# Development

The committed devenv module is the development-toolchain and task boundary.
Enter it interactively with:

```bash
devenv shell
```

The flake imports the same package definition, so the compatible Nix interface
provides the toolchain directly:

```bash
nix develop --accept-flake-config
```

For one-off commands, keep the boundary explicit:

```bash
devenv shell -- cargo --version
devenv shell -- packer version
```

The default shell provides the repository's pinned Rust compiler and tooling,
Nix language tools, Packer, GitHub CLI, Secretspec, and workflow and shell
linters.

## Validate a change

Run the complete flake-packaged CI contract before publishing:

```bash
nix run --accept-flake-config .#nixoa-ci -- check --no-write-lock-file
```

The task graph delegates domain logic to one flake-owned interface:

```bash
nix run --accept-flake-config .#nixoa-ci -- help
nix run --accept-flake-config .#nixoa-ci -- classify-paths < changed-paths.txt
nix run --accept-flake-config .#nixoa-ci -- installer build-input
nix eval --json .#lib.ciPlans.x86_64-linux.validation
nix run --accept-flake-config .#validate-ci-plan -- \
  --plan lib.ciPlans.x86_64-linux.validation
```

GitHub workflows call `nixoa-ci` directly through the flake for build and
release commands. Devenv remains a local convenience facade over the same
package. Product operations use `nxcli`; delivery automation uses `nixoa-ci`.

The `validation` and `installer` target sets are versioned pure values under
`lib.ciPlans.x86_64-linux`. Core builds them with the validator supplied by its
locked Xen Orchestra input. The validator rejects malformed or duplicate
attributes before building, runs each target in a fresh child process against
the shared Nix store, and collects every failure before it exits.

For a focused Rust edit:

```bash
devenv shell -- bash -lc \
  'cd pkgs/nixoa-menu && cargo fmt --check && cargo check --locked && cargo test --locked'
```

The flake exposes separate cached checks for automation, installer-input,
release, operator, and Secretspec contracts, plus ShellCheck, workflow policy
(`actionlint`, `zizmor`, and YAML-aware assertions), and repository invariants.
This keeps failures focused while `ci:check` runs the complete flake and
formatting contracts. Run focused fixtures through devenv, then finish with
the full task graph.

## Cache behavior

The cache layers have separate responsibilities:

- Cachix stores Nix derivation outputs and shares them between jobs and runs.
- The immutable `nixoa-installer` artifact stores the tested ISO, SPDX and
  CycloneDX SBOMs, checksums, attestable state, and artifact pointer.

Only local pure validation tasks use devenv's `execIfModified`. Hosted CI,
installer creation, releases, and lock updates always execute the flake app.

Both `flake.lock` and `devenv.lock` are committed. Refresh them together with
the scheduled updater; `nix run .#nixoa-ci -- locks validate` verifies
that their shared nixpkgs and devenv pins match.

## Work with changes

Use Jujutsu for local repository work:

```bash
jj status
jj diff
jj describe -m 'type(scope): summary'
jj bookmark set my-change -r @
jj git push --bookmark my-change
```

Protected `main` requires the stable `CI gate`. Maintenance bots and release
automation use narrowly validated pull requests rather than writing around
that protection. See [Project reference](project-reference.md) for the
immutable installer state, caches, SBOMs, attestations, and release flow.

[Back to documentation](index.md)
