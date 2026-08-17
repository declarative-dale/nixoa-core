<!-- SPDX-License-Identifier: Apache-2.0 -->
# Development

The committed devenv module is the development-toolchain and task boundary.
Enter it interactively with:

```bash
devenv shell
```

The flake imports the same package definition, so tools remain available when
only the Nix interface is installed without evaluating devenv's task engine:

```bash
nix develop --accept-flake-config
```

For one-off commands, keep the boundary explicit:

```bash
devenv shell -- cargo --version
devenv shell -- packer version
```

The default shell provides the Rust compiler and tooling, Nix language tools,
Packer, GitHub CLI, Secretspec, and the workflow and shell linters used by this
repository. Do not rely on host-installed Cargo, Packer, or Secretspec versions.

## Validate a change

Run the full task graph before publishing:

```bash
devenv tasks run ci:check
```

The task graph delegates domain logic to one flake-owned interface:

```bash
nix run --accept-flake-config .#nixoa-ci -- help
nix run --accept-flake-config .#nixoa-ci -- classify-paths < changed-paths.txt
nix run --accept-flake-config .#nixoa-ci -- installer build-input
```

GitHub workflows call devenv tasks rather than embedding build or release
commands. Product operations remain under `nxcli`; `nixoa-ci` is contributor
and delivery tooling and is not installed on the appliance.

For a focused Rust edit:

```bash
devenv shell -- bash -lc \
  'cd pkgs/nixoa-menu && cargo fmt --check && cargo check --locked && cargo test --locked'
```

The flake exposes separate cached checks for automation, installer-input,
release, operator, and Secretspec contracts, plus ShellCheck, workflow policy
(`actionlint`, `zizmor`, and YAML-aware assertions), and repository invariants.
This keeps failures focused while `ci:check` runs the full flake and formatting
contracts. Run ad-hoc fixtures through devenv; they are not a substitute for
the task graph.

## Cache behavior

The cache layers have separate responsibilities:

- Cachix stores Nix derivation outputs and shares them between jobs and runs.
- GitHub's cache stores only devenv's evaluation and task SQLite metadata.
- The immutable `nixoa-installer` artifact stores the tested ISO, SPDX and
  CycloneDX SBOMs, checksums, attestable state, and artifact pointer.

Only pure validation tasks use `execIfModified`. Installer asset creation,
release tasks, lock updates, and other operations with external effects always
run. Use the CI `refresh_devenv_cache` dispatch input, or locally pass
`--refresh-eval-cache --refresh-task-cache`, when metadata needs to be rebuilt.

Both `flake.lock` and `devenv.lock` are committed. Refresh them together with
the scheduled updater; `devenv tasks run automation:validate-locks` verifies
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
