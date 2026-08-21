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
nix run --accept-flake-config .#nixoa-ci-repository-audit -- --no-write-lock-file
```

Use the leaf packages directly for individual automation operations:

```bash
EVENT_NAME=workflow_dispatch VALIDATE_ONLY=true \
  nix run --accept-flake-config .#nixoa-ci-route
nix run --accept-flake-config .#nixoa-ci-classify-paths < changed-paths.txt
nix run --accept-flake-config .#nixoa-ci-build-input
nix eval --json .#lib.ciPlans.x86_64-linux.validation
nix run --accept-flake-config .#run-ci-plan -- \
  --plan lib.ciPlans.x86_64-linux.validation
```

GitHub workflow command bodies invoke declared tasks through the thin pinned
`devenv` flake app. Each task resolves an explicit `nixoa-ci-*` leaf package;
there is no umbrella automation dispatcher. Workflow YAML retains only GitHub
runner, permission, environment, artifact, and attestation boundaries. Product
operations use `nxcli`; delivery automation uses Nix-packaged leaf programs.
Automation programs and security-sensitive XO helpers remain native shell
sources, while Nix provides their runtime dependencies and executable app
boundaries.

Workflow policy allowlists Actions only for GitHub-platform boundaries:
checkout, Determinate Nix bootstrap, artifact upload/download, attestations,
and FlakeHub's OIDC publication. Linters, formatters, compilers, Cachix, and
repository orchestration are ordinary pinned executables supplied by Nix, so
the same commands run locally and on hosted runners.

Hosted leaf tasks use Devenv's `--mode single` so they execute only the named
boundary. The aggregate `ci:repository-audit` task remains dependency-aware
and has no command of its own after its declared flake and formatting checks
finish.

The `nixoa-ci-route` command emits one versioned JSON route plan. Installer
allocation, protected-main publication, and the required verdict all consume
that exact output, so downstream jobs cannot independently reinterpret
classification or reuse state. Both the router and verdict validate
`nix/automation/ci-plan.schema.json`; schema-v1 rejects undeclared fields,
invalid build-input digests, and publication without installer validation.
The installer policy applies the same relevant/ignored path rules to event
classification and the immutable tracked-file fingerprint; unrecognized paths
therefore invalidate reusable state instead of merely scheduling resolution.
Pull requests and pushes fetch full history for path classification;
scheduled and manual validation use the default shallow checkout. Dormant
merge-group support accepts a diff only when both event SHAs exist and the base
is an ancestor of the head, otherwise it requires installer validation.

The `validation`, `installer`, and `publish` target sets are versioned pure values under
`lib.ciPlans.x86_64-linux`. Core builds them with the validator supplied by its
locked Xen Orchestra input. The schema-v2 runner rejects malformed or duplicate
targets before building, runs each target in a fresh child process against
the shared Nix store, and collects every failure before it exits.

For a focused Rust edit:

```bash
devenv shell -- bash -lc \
  'cd pkgs/nixoa-menu && cargo fmt --check && cargo check --locked && cargo test --locked'
```

The flake exposes separate cached checks for automation, installer-input,
release, operator, and Secretspec contracts, plus ShellCheck, workflow policy
(`actionlint`, `zizmor`, and YAML-aware assertions), and repository invariants.
This keeps failures focused while `ci:repository-audit` runs the complete flake and
formatting contracts. Run focused fixtures through devenv, then finish with
the full task graph.

## Cache behavior

The cache layers have separate responsibilities:

- Cachix stores Nix derivation outputs and shares them between jobs and runs.
- The immutable `nixoa-installer` artifact stores the tested ISO, SPDX and
  CycloneDX SBOMs, checksums, attestable state, and artifact pointer.

Only local pure validation tasks use devenv's `execIfModified`. Hosted tasks
always execute and delegate their implementation to flake-packaged programs;
dependency-free tasks run in isolated single-task mode.

Both `flake.lock` and `devenv.lock` are committed. Refresh them together with
the scheduled updater; `nix run .#nixoa-ci-lock-validate` verifies
that their shared nixpkgs and devenv pins match. The root Nixpkgs and Home
Manager inputs use FlakeHub's `/0` stable release trains, and Home Manager
follows the root Nixpkgs input. FlakeHub reserves `/0.1` for rolling unstable
releases, so the repository contract rejects either root input moving there.

## Work with changes

Use Jujutsu for local repository work:

```bash
jj status
jj diff
jj describe -m 'type(scope): summary'
jj bookmark set my-change -r @
jj git push --bookmark my-change
```

Protected `main` requires the stable `Required CI verdict`. Maintenance bots and release
automation use narrowly validated pull requests rather than writing around
that protection. See [Project reference](project-reference.md) for the
immutable installer state, caches, SBOMs, attestations, and release flow.

[Back to documentation](index.md)
