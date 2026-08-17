<!-- SPDX-License-Identifier: Apache-2.0 -->
# Development

The flake is the development-toolchain boundary. Enter it interactively with:

```bash
nix develop --accept-flake-config
```

For scripts and automation, keep the boundary explicit:

```bash
nix develop --accept-flake-config --command cargo --version
nix develop --accept-flake-config --command packer version
```

The default shell provides the Rust compiler and tooling, Nix language tools,
Packer, GitHub CLI, and the workflow and shell linters used by this repository.
Do not rely on host-installed Cargo or Packer versions.

## Validate a change

Run the full flake contract before publishing:

```bash
nix flake check --accept-flake-config --no-write-lock-file
```

For a focused Rust edit:

```bash
nix develop --accept-flake-config --command bash -lc \
  'cd pkgs/nixoa-menu && cargo fmt --check && cargo check --locked && cargo test --locked'
```

The flake exposes separate cached checks for behavioral fixtures, ShellCheck,
workflow policy (`actionlint` and `zizmor`), and repository invariants such as
release trust, cache topology, action pins, and removed runners. This keeps a
failure focused while `nix flake check` remains the single full contract. Use
`NIXOA_SKIP_EVAL=1 tests/run.sh` only for a quick fixture pass; it is not a
substitute for the full flake check.

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
