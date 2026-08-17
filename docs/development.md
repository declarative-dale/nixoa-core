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
Packer, GitHub CLI, Secretspec, and the workflow and shell linters used by this
repository. Do not rely on host-installed Cargo, Packer, or Secretspec versions.

## Validate a change

Run the full flake contract before publishing:

```bash
nix flake check --accept-flake-config --no-write-lock-file
```

Repository automation has one flake-owned interface:

```bash
nix run --accept-flake-config .#nixoa-ci -- help
nix run --accept-flake-config .#nixoa-ci -- classify-paths < changed-paths.txt
nix run --accept-flake-config .#nixoa-ci -- installer build-input
```

GitHub workflows call the same interface. Product operations remain under
`nxcli`; `nixoa-ci` is contributor and delivery tooling and is not installed
on the appliance.

For a focused Rust edit:

```bash
nix develop --accept-flake-config --command bash -lc \
  'cd pkgs/nixoa-menu && cargo fmt --check && cargo check --locked && cargo test --locked'
```

The flake exposes separate cached checks for automation, installer-input,
release, operator, and Secretspec contracts, plus ShellCheck, workflow policy
(`actionlint`, `zizmor`, and YAML-aware assertions), and repository invariants.
This keeps failures focused while `nix flake check` remains the single full
contract. Run any ad-hoc shell fixtures through `nix develop`; they are not a
substitute for the flake check.

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
