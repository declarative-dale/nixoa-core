<!-- SPDX-License-Identifier: Apache-2.0 -->
# Changelog

All notable changes to published NiXOA releases are documented here. This
project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) beginning with
version 1.1.0. Earlier development records are preserved below and may not
correspond to published GitHub tags.

## [Unreleased]

### Changed

- Run declared CI, release, and automation tasks through their leaf Nix
  packages instead of routing hosted execution through the monolithic
  `nixoa-ci` dispatcher, disable the unrelated development package set on
  hosted task runners, and remove that umbrella CLI entirely.

## [1.3.0] - 2026-08-20

NiXOA 1.3.0 adds explicit Xen Orchestra package channels and consolidates the
appliance's native configuration and automation contracts.

### Changed

- Select xo-nixpkg's `latest` package output by default, expose typed
  `latest`/`stable`/`rolling` XO channel policy, and refresh the input branch
  without relying on deprecated moving Git tags.
- Replace the generated Xen Orchestra system override with the checked-in
  `host/config.nixoa.toml` source selected by `nixoa.xo.config.file`, layered
  over the package's immutable vendor defaults; remove the former inline
  `nixoa.xo.config.toml` interface.
- Keep CI plans, installer classification, and repository rules as native JSON,
  and keep the `nixoa-ci` dispatcher and XO storage/TLS helpers as lintable
  shell sources instead of dense embedded Nix strings.
- Make the versioned JSON emitted by `nixoa-ci prepare` the sole downstream CI
  planning contract for installer builds, protected-main publication, and the
  stable gate; route hosted commands through declared devenv tasks backed by
  repository-native automation programs and thin flake apps.
- Limit full-history CI checkouts to path-classifying events, fail safely when
  future merge-group SHAs are incomplete or non-ancestral, run hosted leaf
  tasks in isolated Devenv mode, and serialize rolling and versioned FlakeHub
  publication through one non-canceling queue. Validate both lifecycle-plan
  production and consumption against one strict schema-v1 JSON contract, and
  use one path policy for classification and installer-state fingerprinting.

### Fixed

- Remove each temporary CIFS credential file after its mount attempt instead
  of losing the function-local cleanup path before the process exit trap ran.

## [1.2.1] - 2026-08-18

NiXOA 1.2.1 is a corrective release of the 1.2.0 feature set on a unique,
verified Git tag. It preserves the tested installer and curated notes while
strengthening release preparation against historical tag collisions and
redundant trusted-CI dispatches.

### Changed

- Route the final `CI gate` and synchronized native/flake lock refresh through
  flake-packaged commands, leaving workflow YAML responsible only for GitHub
  runner, permission, environment, artifact, and attestation boundaries.
- Inventory every automation shell source and every workflow `run` step from a
  pure Nix repository policy, rejecting unwrapped scripts and direct workflow
  orchestration before CI can drift.

### Fixed

- Reject a release candidate when its semantic-version tag already exists
  without a matching GitHub release, preventing immutable assets from being
  associated with an unrelated historical Git ref.
- Wait one discovery interval for a bot-authored pull-request workflow before
  dispatching exact-head fallback CI, avoiding duplicate validation when
  GitHub delivers the pull-request event shortly after PR creation.
- Publish the current 1.2 release line as `v1.2.1`, whose tag and immutable
  release both identify the protected source commit.

## [1.2.0] - 2026-08-18

NiXOA 1.2.0 makes the flake the reusable source of truth for validation,
installer construction, and publication. Core now consumes Xen Orchestra's
integrated FUSE 3 libvhdi package and shared schema-v2 plan runner, while
protected CI builds, verifies, and publishes only the outputs declared by
those plans.

### Added

- Add `validation`, `installer`, and `publish` schema-v2 plans as pure flake
  attributes, including deterministic target names, result links, and output
  manifests.
- Add the `flake-plan-runner` package, `run-ci-plan` app, and `nixoa-ci plan`
  command as the supported interface for validating and executing CI plans.
- Add flake-packaged lock refresh and allowlisted update-PR publication,
  replacing repository-specific workflow scripting.

### Changed

- Consume the sole FUSE 3 `libvhdi` package integrated into the Xen Orchestra
  flake and use the consolidated Xen Orchestra input graph and cache contract.
- Run every hosted workflow command directly through the flake-packaged
  `nixoa-ci` interface, including QEMU boot validation, publishing, release,
  trusted-update, and synchronized lock maintenance. Devenv remains available
  as a local development facade.
- Consolidate repository validation and installer-state planning on one runner,
  make the stable gate dependency-free, and publish only planned closures to
  Cachix after protected-main validation succeeds.
- Reuse an exact, attested pull-request installer result on protected `main`
  instead of rebuilding an unchanged ISO before publication.
- Refresh the locked Nix, devenv, Home Manager, and Xen Orchestra dependency
  graph through the repository's native update path.

### Removed

- Remove the standalone libvhdi flake/cache dependency and the legacy CI-plan
  compatibility aliases. Consumers must use `packages.flake-plan-runner`,
  `apps.run-ci-plan`, or `nixoa-ci plan`.

### Fixed

- Dispatch exact-head CI when a repository-token automation pull request cannot
  emit a pull-request event, then let the required gate control auto-merge.
- Treat immutable release retries as verification: published assets and their
  exact source commit are accepted without attempting a forbidden mutation.

## [1.1.2] - 2026-08-17

Version 1.1.2 consolidates NiXOA's build and delivery contract behind the core
flake and devenv. It makes Cachix the shared Nix cache, preserves verified
installer and SBOM outputs as immutable artifacts, and avoids rebuilding an
unchanged appliance after it has passed boot and provenance checks.

### Added

- Add a native devenv 2.2 task graph for local checks, CI, releases, and input
  maintenance. It shares one package definition with the lightweight,
  compatible `nix develop` shell.
- Persist only devenv's evaluation and task metadata between GitHub runs, with
  an explicit dispatch control for invalidating both caches.
- Add the flake-packaged `nixoa-ci` interface for local and GitHub automation,
  including installer classification and state, trusted updates, and the
  immutable release state machine.
- Add a flake-validated Secretspec contract for Cachix's GitHub repository
  secret and variable, with token-free pull-request and required publishing
  profiles.

### Changed

- Rework the README around immediate launch and local-build paths, with
  operations, customization, troubleshooting, architecture, and contributor
  details organized behind a task-oriented documentation index.
- Route every GitHub workflow command through named devenv tasks while keeping
  permissions, SecretSpec resolution, Cachix streaming, artifacts, and
  attestations at the GitHub boundary.
- Refresh and validate `devenv.lock` and `flake.lock` in one Determinate update
  pull request, with trusted automation restricted to those two files.
- Reduce GitHub workflows to permissions, runner setup, artifact transport,
  attestations, and calls into `nixoa-ci`; repository-specific decisions are
  now reproducible through the flake.
- Declare installer-impact and build-input paths in one Nix policy, and split
  automation, installer-state, release, operator, Secretspec, workflow, and
  shell fixtures into independently cached checks.
- Replace Magic Cache and the temporary closure artifact bridge with Cachix
  daemon sharing for every Nix-producing CI job. Trusted events publish all new
  build outputs; fork pull requests consume the same public cache read-only.
- Cache the tested ISO, SPDX and CycloneDX inventories, checksums, and immutable
  state together in one 90-day GitHub artifact used by later runs and releases;
  Cachix separately shares the system closure and SBOM tooling between jobs.
- Validate workflow structure with Actionlint, Zizmor, and YAML-aware action
  pin and direct-script policies.
- Keep the stable required-status gate independent of Nix, Cachix, devenv, and
  secrets so cancellations and metadata-only pull requests finish promptly.

### Fixed

- Remove the external release-token assumption from protected version and
  flake-input updates. Repository-scoped automation now dispatches CI for the
  exact bot-authored head SHA and validates version-only changes before merge.
- Canonicalize GitHub's `app/` author prefix before validating trusted bot
  identities, allowing token-free version pull requests to enter CI while
  retaining the exact expected-author check.
- Select trusted-update CI runs by their reported head SHA, preventing a stale
  run for an earlier version-branch commit from entering the merge decision.
- Approve GitHub's gated pull-request CI with the repository-scoped Actions
  permission, then compare the trusted branch with current `main` before
  selecting its exact-head validation.
- Reuse healthy exact-head pull-request validation already in progress and
  reject stale runs before enabling auto-merge.
- Wait for GitHub's refreshed pull-request head to become visible before
  selecting its exact-head validation and enabling auto-merge.
- Restrict formatting checks to source-controlled Nix files, excluding
  generated devenv state while retaining a jj-compatible local fallback.

## [1.1.1] - 2026-08-17

Version 1.1.1 corrects the protected post-release handoff and makes CI policy
failures smaller, clearer, and more reusable through the flake.

### Changed

- Split workflow security, ShellCheck, behavioral fixtures, and repository
  policy into independent flake checks so Nix can cache and report each
  contract separately.
- Evaluate stable versioning, cache topology, release integrity, action pins,
  dependency automation, and removed-runner invariants from Nix expressions.

### Fixed

- Require an external automation token before creating protected version PRs,
  validate its configured owner, and fail immediately instead of opening a
  `GITHUB_TOKEN` PR that cannot trigger the required pull-request CI event.

## [1.1.0] - 2026-08-17

Version 1.1.0 is a security and delivery overhaul. It strengthens the path
from source commit to immutable installer release while leaving the appliance's
core deployment model unchanged.

### Security

- Verify release candidates against the exact source commit, CI workflow,
  build provenance, checksums, and SPDX predicate before publication.
- Publish through a verified draft, attest the final installer filename and
  its SBOM, then rely on GitHub immutable releases to prevent replacement of
  the tag or assets.
- Pin every third-party GitHub Action to a full commit SHA, audit workflows
  with `zizmor`, and grant signing and write permissions only to the jobs that
  require them.
- Restrict automated merges to the expected bot identity, repository, branch,
  title, and head commit; protected `main` still requires the current `CI gate`.

### Added

- Generate SPDX and CycloneDX runtime inventories with `sbomnix`, validate and
  checksum both documents, and ship them with the installer and a release
  manifest.
- Add signed build attestations, a QEMU boot smoke test, deterministic installer
  fingerprints, and an immutable state pointer for selecting verified build
  artifacts.
- Add grouped GitHub Actions and Cargo dependency updates, including a dedicated
  Rust security-update group, plus weekly Determinate flake-input updates.
- Provide the supported Nix, Rust, Packer, workflow, and security toolchain
  through `nix develop`.

### Changed

- Consolidate source checks, build planning, installer production, boot testing,
  attestations, and rolling publication into one conditional CI graph with a
  stable required status.
- Reuse an existing verified installer when its content fingerprint is unchanged;
  documentation and other metadata-only changes avoid unnecessary builds, while
  a forced validation runs every other month.
- Use Determinate Magic Cache only for validation and installer-build jobs. The
  verified build hands its four reusable closures to the publication job as a
  14-day, file-backed Nix cache selected by immutable run ID. Publication then
  sends those exact closures to the retained public Cachix cache and FlakeHub,
  avoiding both a rebuild and a redundant Magic Cache upload.
- Derive versions from the latest published GitHub release, beginning with the
  `v1.0` baseline, and route release and post-release version changes through
  protected pull requests.
- Publish rolling FlakeHub builds on the `0.2` line, use current Node.js 24
  action revisions, and keep a verified installer usable if an external rolling
  publication fails.
- Refresh the Xen Orchestra closure and verify that the exact installer output
  is present in its public Cachix cache.

### Fixed

- Split installers larger than GitHub's 2 GiB release-asset limit into numbered,
  checksummed parts while retaining provenance and SBOM attestations for the
  reconstructed versioned ISO.
- Record the successful Packer apply at template seal time so a new clone does
  not report a rebuild before its configuration changes.
- Create NFS status directories before service startup and remove obsolete Nix
  generations while sealing templates.
- Limit the Xen Orchestra first-boot grace period to the initial readiness check.
- Reduce the native template disk default and minimum from 40 GiB to 20 GiB.

## v0.9.1 — Cache-Rich Native Template Deployment

Date: 2026-07-31

Compared with v2.0.0, this release refocuses the repository on one x86_64
XCP-ng guest, `nixosConfigurations.nixoa`, and adds a cache-rich native template
deployment path.

### Changed

- Replaced the exported `nixoaCore` namespace and host-template framework with
  one Den host composed from platform, XCP-ng, XO, and operator aspects.
- Replaced untyped host context plumbing with native NixOS options under
  `nixoa.operator` and `nixoa.xo`.
- Consolidated XO into service, TLS, and storage modules while retaining
  Valkey, certificate automation, remote storage, and privilege separation.
- Made `.#nixoa` the fixed target for bootstrap, `nxcli`, apps, and the TUI.
- Moved hand-maintained settings, generated hardware, and generated menu
  overrides into the single `host/` tree.
- Enabled a constrained NoCloud/cloud-init path for per-clone machine identity
  and `nixoa` SSH-key injection without delegating networking, disks, packages,
  or arbitrary scripts to cloud-init.
- Added an on-demand `deploy-template` flake app that downloads a prebuilt
  minimal installer ISO by default and creates a verified, identity-cleared
  native XCP-ng template through a Nix-provided Packer and pinned Vates
  XenServer plugin. A local flake build remains available as a fallback.
- Use Determinate Systems' unauthenticated bootstrap binary cache for installer
  and first-install builds instead of the authenticated FlakeHub Cache endpoint.
- Update Determinate Nix from 3.21.0 to 3.21.9, whose exact package output is
  available from the official bootstrap binary cache.
- Refresh the complete flake lock, including nixpkgs, Home Manager, and
  import-tree, before publishing the cached appliance closure.
- Build the complete NiXOA system closure and unattended installer in GitHub
  Actions, while using the public NiXOA Cachix cache during installer and
  first-install builds.
- Keep the official Determinate and NiXOA Cachix substituters on installed
  appliances, and wrap only Determinate's cached runtime output so NixOS does
  not rebuild its uncached manual/debug development outputs.
- Enable the standard polkit authorization path so `systemd-networkd` can
  apply transient hostnames supplied by DHCP.
- Preseed the unattended installer ISO with the complete NiXOA system,
  `nixoa-menu`, and Xen Orchestra closures. Push only the smaller reusable
  deployer, CLI, metadata, and menu closures to the GitHub-managed Cachix cache.
- Declare the public package caches in the flake, publish the Packer deployer
  through Cachix, and retain the multi-gigabyte preseeded installer as a
  checksum-verified GitHub Actions artifact instead of consuming the 5 GB
  NiXOA Cachix allocation with its complete closure.
- Resolve the GitHub installer artifact at deployment time through the flake's
  `deploy-template` app. The artifact is intentionally not a flake input: the
  helper selects the newest successful `main` workflow run, downloads it to a
  temporary directory, verifies its published checksum, and passes it directly
  to Packer.
- Grow the root partition and filesystem through cloud-init when an XCP-ng
  clone is provisioned with a larger virtual disk.
- Give Xen Orchestra a four-minute startup grace period and then wait for its
  HTTPS listener during Packer verification instead of treating the service
  process becoming active as endpoint readiness.
- Check every flake input for updates each Wednesday and create or refresh a
  dedicated lock-file pull request without changing `main` until it is merged.
- Prevent installer and rolling FlakeHub rebuilds when a push changes only
  documentation, Markdown, README, or changelog files. Version-tag pushes
  continue to publish releases.

### Removed

- Physical/VM duplication, `nixo-ce-example`, `-vm`, and `vm` aliases.
- `nxcli host add`, `host list`, `host select-vm`, and target selection.
- Forced Xen disk paths, initrd NFS/repartition policy, Flatpak and Prometheus
  scaffolding, raw module/config escape hatches, and unused helper libraries.
- The obsolete XO launcher-repair wrapper.

### Security

- Final SSH access is restricted to the declared `nixoa` operator rather than
  retaining permanent access for the installer `nixos` account.
- Protect files on the EFI system partition with owner-only masks so the
  systemd-boot random seed is not world-readable.

### Fixed

- Detect the XO HTTPS listener from its rendered TOML instead of using a
  malformed `sed` expression that prevented `nixoa-menu` from starting.
- Read generated `lib.mkDefault` operator values and Nix store package hashes
  correctly so the menu preserves SSH keys and reports the XO version.
- Disable cloud-init network rendering explicitly so systemd-networkd remains
  authoritative, and remove stale fallback network files during activation.
- Avoid first-boot races between cloud-init and NixOS SSH host-key generation,
  and suppress unsupported SSH key-to-console output on NixOS.

## v2.0.0 — Operator Console And CLI Refactor

Date: 2026-05-08

This release is a breaking repository and operator-surface refactor. NiXOA is now operated directly from the `core` repo: reusable aspects, host templates, concrete host definitions, packages, apps, `nxcli`, and `nixoa-menu` all live in one flake. The previous model, where a separate system flake consumed `core` as an input and owned host operations, is deprecated.

The release also turns `nixoa-menu` into an xsconsole-style SSH console, makes `nxcli` the single supported command surface for repository and host operations,
and removes the older duplicate script entrypoints that previously owned apply, commit, diff, history, log, and XOA update flows.

### ✨ Added

- **xsconsole-style `nixoa-menu` navigation** with a compact `NiXO-CE` header, one visible left menu at a time, persistent contextual right-side panels, and simple Up/Down/Enter/Esc navigation
- **Selectable shell-return confirmation** on Esc from the main menu, with arrow-key selection plus `y`, `n`, and Esc shortcuts
- **Apply-time dirty-worktree commit prompt** in `nixoa-menu`; dirty tracked files are listed before apply, operators can enter a commit message, and an automatic dated message is generated when the prompt is left blank
- **`nixoaMenuAutoStart` host context setting**, defaulting to `false`, to make SSH console autostart explicitly opt-in
- **`nxcli` parity commands** for `commit`, `diff`, `history`, `status --json`, host JSON output, flake update previewing, and XOA-specific input updates
- **Full `nxcli` reference documentation** covering every command, option, example, and flake app wrapper
- **Baseline Bash operator quality-of-life defaults** such as persistent history, readline search/completion behavior, and core Git/system aliases without requiring extras

### 🔄 Changed

- **Core is now the operational repo**, not only a reusable input; concrete host directories, automation aliases, packages, apps, CLI behavior, and console behavior are consolidated into this flake
- **Host-owned state now lives under `core/host/<hostname>/`** with `host/_automation/default.nix` selecting the stable `nixosConfigurations.vm` output
- **`nxcli` is now the canonical operator interface** for host creation, apply, boot, rollback, commit, diff, history, status, flake updates, XOA input updates, and XO log tailing
- **Flake apps now route through packaged `nxcli`** for apply, commit, diff, and history instead of resolving repo-local helper scripts at runtime
- **`nxcli` packaging now uses `writeShellApplication`** with explicit Nix-provided runtime inputs, removing ambient tool and script-local `nix shell nixpkgs#nh` fallback behavior
- **`nixoa-menu` uses `nxcli` for apply, rollback, and commit flows**, keeping TUI host-context edits in `scripts/tui/` and repository/system actions in the CLI
- **SSH login behavior changed** so Bash and Zsh start `nixoa-menu` only when `nixoaMenuAutoStart = true;`, while preserving `NIXOA_TUI_BYPASS` and `NIXOA_TUI_ACTIVE` guards
- **TUI update actions use `nix flake update <input>`** instead of deprecated `nix flake lock --update-input` commands
- **Documentation now describes the current operator model**, including a streamlined README, manual `nixoa-menu`, `nxcli commit` for saving flake changes, XOA input updates, and the reduced role of direct scripts
- **`nixoa-menu` package version advanced to `0.6.0`** and `nxcli` reports version `4.1.0`

### ⚠️ Deprecated

- **The old split `core` input plus separate `system` flake model** for day-to-day NiXOA operation; new installations and operators should use the unified `core` flake directly
- **System-flake-owned host operations** such as applying, committing, updating, and launching the console from outside `core`; these are now `nxcli` and `nixoa-menu` responsibilities inside this repo

### 🗑️ Removed

- **Deprecated duplicate operator scripts** for apply, commit, diff, history, and XOA updates now that their behavior lives in `nxcli`.
- **Standalone XO log helper script** after moving log tailing into `nxcli xo logs`
- **Obsolete Redis-to-Valkey migration script** that was no longer referenced by docs, apps, modules, or current operator flows
- **ASCII-art console header and simultaneous main-menu/submenu rendering** in favor of the compact operator-console layout

### 🐛 Fixed

- **Apply configuration can no longer silently proceed past dirty tracked files in the TUI** without first asking whether to commit them
- **Confirmation styling now matches the console palette** instead of using an out-of-band danger window for the shell-return prompt
- **Docs and repo guidance no longer point at removed helper scripts** for logs or routine operator tasks

## v1.7.0 — Shared Console Release And XO Cache Alignment

Date: 2026-04-05

This release turns `core` into the shared source of truth for the NiXOA
console, aligns the Xen Orchestra package resolution with the exact upstream
`xo-nixpkg` derivation, and ships a larger console refactor focused on cleaner
navigation, better layout behavior, and lower bootstrap build overhead.

### ✨ Added

- **Shared `nixoa-menu` package ownership in `core`** so downstream consumers can reuse one cached console build
- **Page-based console navigation** with `Dashboard`, `Configure`, `Software`, `Maintenance`, and `Logs`
- **Searchable command palette and dedicated help modal** for faster keyboard-driven action discovery
- **Typed alert model** with severity levels and optional action affordances
- **Scrollable and filterable log browsing** through a dedicated `Logs` page plus a smaller dashboard activity panel

### 🔄 Changed

- **`xen-orchestra-ce` resolution** now follows the exact `xo-nixpkg` derivation path instead of re-materializing it through `core`'s own nixpkgs graph
- **`libvhdi` defaults** now come directly from the `xo-nixpkg` input graph rather than a separate `core`-owned package export
- **Console layout hierarchy** now uses stable domain tabs, grouped action menus, footer shortcuts, and consistent gutters/padding
- **Console labels and maintenance terminology** now use clearer task names such as `System Summary`, `Recent Activity`, `Flake Inputs`, `Rollback Generation`, and `Run Garbage Collection`
- **Console package version** advanced to `0.3.1`

### 🗑️ Removed

- **Flat top-level action list** that mixed unrelated configuration, software, and maintenance tasks into one overloaded menu
- **Red as a generic active-state color** outside true errors or destructive actions

### 🐛 Fixed

- **Border collisions and clipped panes** in the Ratatui console layout by rebuilding the screen around gutters and adaptive panel sizing
- **TUI/backend drift** by moving the shared console binary into `core` while keeping host-mutating repo actions in `system`
- **Cache misses for Xen Orchestra builds** caused by `core` resolving a different derivation than the one published by `xo-nixpkg`
- **Update coverage for Determinate Nix** by exposing `determinate` as a first-class `Check for Updates` flake input in the console

## v1.6.0 — Den Alignment And Output Naming Cleanup

Date: 2026-04-04

This release aligns `core` with the current Den patterns, removes obsolete
inputs that Den no longer needs, and renames the public output wiring so the
repository is easier to follow for maintainers consuming `nixosModules`,
packages, and overlays.

### ✨ Added

- **Den flake output module support for packages** in the non-`flake-parts` output path

### 🔄 Changed

- **Den input updated** to the current `6d6ff64` release line
- **Bootstrap module renamed** from `modules/dendritic.nix` to `modules/den.nix`
- **Public module export entrypoint renamed** from `stacks.nix` to `nixosModules.nix`
- **Output wiring** now reads more directly from `den` bootstrap to named public outputs

### 🗑️ Removed

- **Obsolete `flake-aspects` input** now that Den bundles its own aspect support
- **Unused `import-tree` input** from the root `core` flake

### 🐛 Fixed

- **Repository drift against current Den docs** by removing stale dependency patterns and adopting the current output module layout

## v1.5.0 — Boundary Completion And XO Runtime Defaults

Date: 2026-03-25

This release finishes the remaining core/system split by removing host
lifecycle policy from core, moving Xen Orchestra service identity into typed
core options, and aligning the docs with the simplified host workflow.

### ✨ Added

- **Typed XO service identity options** through `nixoa.xo.user` and `nixoa.xo.group`

### 🔄 Changed

- **XO service/storage modules** now consume `config.nixoa.xo.*` defaults for service identity
- **Consumer docs** now describe core as a runtime library with host policy delegated to `system/`
- **Operational examples** now use the simplified `system` apply flow without requiring an explicit hostname argument

### 🗑️ Removed

- **Remaining host-owned platform modules** for boot loader policy, system state version, and extras tooling

### 🐛 Fixed

- **Last core/system boundary leaks** around boot policy, timezone/state ownership, and XO service-account defaults

## v1.4.0 — Den-Native Naming And Boundary Cleanup

Date: 2026-03-25

This release tightens the boundary between the immutable appliance library and
the host flake, removes redundant naming layers, and renames the live module
tree to match the current dendritic structure more closely.

### ⚠️ Breaking Changes

- **`nixosModules.xo` was removed**; the explicit `xenOrchestra` stack is now the only XO export
- **Plain module paths moved** from `modules/_nixos/` to `modules/nixos/`
- **Host identity and admin-user policy moved out of core**; hostname, SSH, sudo, and admin account policy now belong to `system`

### ✨ Added

- **Dedicated Xen Orchestra service modules** for the service account and runtime limits
- **Explicit `stacks.nix` entrypoint** for public stack composition

### 🔄 Changed

- **Feature slice naming** from `foundation` to `shared` and from `xo` to `xen-orchestra`
- **Platform package module name** from `base-packages.nix` to `packages.nix`
- **README and architecture docs** to reflect the current output surface and implementation tree

### 🐛 Fixed

- **Core/system responsibility drift** by removing host-owned identity policy from the core appliance library

## v1.3.0 — Explicit Output Surface And System Boundary Cleanup

Date: 2026-03-24

This release finalizes the dendritic core refactor around explicit flake
entrypoints, curated stack exports, and a cleaner separation between the core
appliance library and the system host flake.

### ⚠️ Breaking Changes

- **Public output layout changed** from the old top-level output files to `modules/outputs/`
- **Granular stack exports are now part of the public API** through `virtualization` and `xenOrchestra`
- **Bootstrap/install responsibilities were removed from core** and now live in `system/`

### ✨ Added

- **Explicit output entrypoints** in `modules/outputs.nix` and `modules/outputs/default.nix`
- **Granular public stack exports**: `virtualization` and `xenOrchestra`
- **Condensed architecture/docs pass** aligned with the new output surface

### 🔄 Changed

- **Public flake loading** now uses explicit dendritic entrypoints from `flake.nix`
- **Curated module exports** now live under `modules/outputs/`
- **Packaged `nixoa` CLI** now targets the current `system/` repository layout
- **README and docs** now describe core as an immutable appliance library rather than a host bootstrap repo

### 🗑️ Removed

- **Unused `home-manager` flake input**
- **Obsolete `scripts/xoa-install.sh`** bootstrap script
- **Legacy top-level output module paths** in favor of `modules/outputs/`

### 🐛 Fixed

- **Output discoverability** after the dendritic refactor by switching from implicit tree loading to explicit module entrypoints
- **System-facing update guidance** in `xoa-update.sh` and the packaged CLI

## v1.2.0 — Platform Dendritic Split

Date: 2026-02-27

This release includes a dendritic refactor,
XO module decomposition, and input compatibility updates.

### ✨ Added

- **Modular utility library** under `lib/utils/` (`get-option`, `options`, `module-lib`, `systemd`, `types`, `validators`)
- **XO module split** into focused files:
  - `options-base.nix`, `options-paths.nix`, `options-tls.nix`
  - `service/start-script.nix`
  - `storage/libvhdi-options.nix`, `storage/sudo-config.nix`, `storage/sudo-init.nix`
  - `tls-tmpfiles.nix`
- **Flake output split** into dedicated parts:
  - `parts/flake/nixos-modules.nix`
  - `parts/flake/outputs.nix`
  - `parts/flake/overlays.nix`
  - `parts/per-system/packages.nix`

### 🔄 Changed

- **Stack and feature key naming**: `system-*` → `platform-*`; appliance composition updated
- **parts/ layout flattened** from `parts/nix/*` into `parts/flake`, `parts/inputs`, `parts/registry`, and `parts/per-system`
- **Registry feature definitions** consolidated into `parts/registry/features.nix` (group sub-files removed)
- **XO/platform filenames normalized** (for example `state-version.nix`, `defaults.nix`, `config-link.nix`, `dev-tools.nix`, `tls-service.nix`)
- **Input sourcing and locks refreshed**:
  - `xen-orchestra-ce` moved from tagged source to beta tracking over HTTPS
  - lock updates include the 6.2.0 update cycle and nixpkgs/tooling refreshes
- **Docs/README/architecture** refreshed for the new structure and composition model

### 🗑️ Removed

- **Bundle-only collector modules** (`default.nix`) in platform and XO service/storage slices
- **Legacy monolithic XO options file** (`modules/features/xo/options.nix`)

### 🐛 Fixed

- **Deprecated Nix attr usage** replaced:
  - `final.system` → `final.stdenv.hostPlatform.system`
  - `pkgs.system` → `pkgs.stdenv.hostPlatform.system`

## v1.1.0 — Dendritic Feature Reorg

Date: 2026-01-27

This release reorganizes the module tree into clearer dendritic feature groups
and moves Xen guest integration into the core virtualization set.

### ✨ Added

- **virtualization/xen-guest.nix** in core (guest agent support)
- **foundation/** feature slice for shared module arguments

### 🔄 Changed

- **Module layout**: `modules/features/system/` → `modules/features/platform/`
- **Registry wiring** updated to match new feature categories
- **Appliance stack** now includes Xen guest integration by default (still gated by vars)
- **Docs/README** refreshed to describe the new layout
- **Dev tooling** moved out of core packages (codex, claude-code now live in system)

### 🗑️ Removed

- **system/virtualization/xen-guest.nix** (moved into core)

---

## v0.5 — Runtime Cleanup & Xen VM Enhancements

Date: 2026-01-09

This release streamlines the runtime configuration, improves Xen VM hardware support, modernizes service configuration, and removes automatic update infrastructure.

### ✨ Added

- **hardware-xen.nix module** - Xen VM hardware configuration with /dev/xvda* device paths instead of UUIDs
  - Automatically maps Xen VM layout: xvda1 → /boot, xvda2 → /, xvda3 → swap
  - Uses lib.mkForce to override UUID-based hardware-configuration.nix
- **Systemd tmpfiles rules** for automatic directory creation:
  - Xen Orchestra symlink from /var/lib/xo/xen-orchestra to Nix store package
  - .ssh directory with proper permissions (0700) before authorized_keys creation

### 🔄 Changed

- **Runtime configuration cleanup** - Removed obsolete configuration settings for cleaner deployment
- **Cachix integration** - Moved cachix configuration to system flake for better organizational structure
- **Redis → Valkey** - Updated services.redis.package = pkgs.valkey for Redis-compatible caching
- **Shell configuration** - Now based on vars.enableExtras instead of deprecated vars.shell variable
- **Swap disabled by default** - Improved performance for typical VM deployments

### 🗑️ Removed

- **Automatic updates infrastructure** - Removed all update modules and automation
  - Deleted modules/xo/updates/ directory (auto-upgrade.nix, common.nix, gc.nix, libvhdi.nix, nixpkgs.nix, xoa.nix)
  - Removed flake/apps.nix (only contained update-xo app)
  - Updates now managed via core git releases (stable/beta branches)
  - Future release will include TUI-based update management interface
  - Users should follow core repository releases and rebuild system manually

### 📚 Documentation

- Updated Xen VM hardware configuration documentation
- Clarified shell selection mechanism based on enableExtras flag
- Documented new update workflow via git releases

---

## v1.0.0 — Milestone Release

Date: 2025-12-29

This milestone release marks nixoa-core reaching production-ready maturity with standardized option naming, modular architecture, and comprehensive feature completeness.

### 🎉 Milestone Achievements

- First stable 1.0.0 release
- Standardized options namespace (`nixoa.*`)
- Highly modular architecture
- Fully reproducible xen-orchestra build created as a nixpkg, pkg/xen-orchestra-ce/default.nix

### ⚠️ BREAKING CHANGES

All options renamed from `xoa.*` to `nixoa.*` namespace:

- `config.xoa.enable` → `config.nixoa.xo.enable`
- `config.xoa.xo.*` → `config.nixoa.xo.*`
- `config.xoa.storage.*` → `config.nixoa.storage.*`
- `config.xoa.autocert.*` → `config.nixoa.autocert.*`
- `config.xoa.extras` → `config.nixoa.extras`

**Migration required** for all existing configurations.

### ✨ Added

- **Snitch network monitor** package for real-time connection monitoring
- **configNixoaFile option** to link `config.nixoa.toml` to `/etc/xo-server/` for runtime config changes, config.nixoa.toml is an override file that operates on top of the default /etc/xo-server/config.toml, which you should not edit directly.
- **boot.nix module** with systemd-boot (endabled by default) + GRUB support with flexible boot configuration toggle
- **Modular updates system** - split `updates.nix` into `updates/` directory:
  - `updates/common.nix` - shared update functionality
  - `updates/auto-upgrade.nix` - system auto-upgrade scheduling
  - `updates/gc.nix` - garbage collection
  - `updates/xoa.nix` - Xen Orchestra updates
  - `updates/nixpkgs.nix` - nixpkgs package updates
  - `updates/libvhdi.nix` - libvhdi library updates
- Made `config.nixoa.toml` readable by `xo` user for runtime configuration access
- Added explicit module imports replacing dynamic discovery

### 🔄 Changed

- Replaced dynamic module bundling with explicit imports in `modules/default.nix`
- Updated `autocert.nix` to use local variables (`httpCfg`, `xoUser`, `xoGroup`)
- Simplified boot configuration logic (removed redundant conditionals)
- Enhanced package references to use `nixoaPackages.xo-ce` directly
- Updated all module option references to new `nixoa.*` namespace
- Improved Node.js v20 → v24 migration in xen-orchestra package

### 🗑️ Removed

- `bundle.nix` (replaced with explicit imports)
- `modules/home/home.nix` (migrated to system)
- `integration.nix` module (functionality distributed)
- Redundant permission checks

### 🐛 Fixed

- Service environment path configuration
- Systemd working directory conflicts
- Package reference scoping issues during module evaluation
- Broken symlinks in xen-orchestra build process
- Git repository handling in Nix sandbox
- Dev dependencies installation in yarn build
- Various syntax errors in configuration files

### 📚 Documentation

- Updated all option references throughout documentation
- Updated CONFIGURATION.md with new option names
- Updated troubleshooting guides with correct file paths

---

## v0.9 — Architecture Refactoring (yarn2nix Packaging & Build System Separation)

Date: 2025-12-24

This major release refactors NiXOA Core from a runtime build system to a pure Nix-packaged solution using yarn2nix. This transformation improves reproducibility, enables binary caching, and reduces deployment time from 45+ minutes to seconds.

### ✨ Added

**Phase 1: Package Definitions**
- Xen Orchestra packaged via yarn2nix in `pkgs/xoa/default.nix` with full Yarn workspace support
- libvhdi extracted as standalone package in `pkgs/libvhdi/default.nix`
- Packages exposed via flake outputs with overlay support for easy integration
- Package verification and artifact validation in build process

**Phase 2: Centralized Utilities**
- New `lib/utils.nix` with reusable helper functions for common patterns
- `getOption` function for safe nested attribute access with defaults
- Helper functions for common Nix patterns: `mkDefaultOption`, `mkEnableOpt`, `mkSystemdService`
- Path and port validation helpers for improved type safety

**Phase 4: Flake Integration**
- Clean separation of build inputs (in nixoa-core) from user configuration (in system)
- Packages and utilities automatically available via nixoa-core's `_module.args`
- Simplified flake inheritance model with zero duplication

### 🔄 Changed

**Phase 3: Module Refactoring (268 lines removed)**

1. **xoa.nix (43% reduction - 618 → 352 lines)**
   - Removed 136-line buildXO script - build now happens at package time
   - Removed 33-line checkXORebuildNeeded script - rebuild detection obsolete
   - Removed nodeWithFuse wrapper - native modules pre-patched in package
   - Removed xo-build.service systemd service - no runtime build needed
   - Updated startXO to use packaged XOA from `/nix/store` (immutable)
   - Removed 4 obsolete options: `appDir`, `webMountDir`, `webMountDirv6`, `buildIsolation`
   - Updated xo-server.service to remove dependency on xo-build.service
   - Updated WorkingDirectory to immutable /nix/store path
   - Removed LD_LIBRARY_PATH (native modules pre-patched)
   - Removed appDir from ReadWritePaths

2. **libvhdi.nix (64% reduction - 112 → 40 lines)**
   - Removed 64-line inline derivation - now in pkgs/libvhdi/default.nix
   - Removed fallback fetchurl logic - source provided by flake inputs
   - Updated package default to reference nixoaPackages.libvhdi

3. **Core Module Utility Refactoring (54 lines removed)**
   - All 6 core modules now use centralized `getOption` from lib/utils.nix
   - Eliminated 9-line `get` function duplication in each module
   - Updated modules: base.nix, networking.nix, packages.nix, services.nix, users.nix, integration.nix
   - Added nixoaUtils to function parameters across all affected modules

**Documentation Updates**
- Updated CONFIGURATION.md: system-settings.toml → configuration.nix, xo-server-settings.toml → config.nixoa.toml
- Updated troubleshooting-cheatsheet.md with new file references
- Updated xo-config.nix comment: "nixoa-config flake" → "system flake"
- Updated all configuration examples to reflect new Nix-based configuration format

### ✨ Benefits

**For Users**
- 10-100x faster deploys: No 45-minute build on every `nixos-rebuild`
- Binary cache eligible: XOA can be pre-built and cached
- Reproducible builds: Same inputs → identical package hash
- Atomic updates: Switch XO versions instantly via rollback

**For Developers**
- Cleaner architecture: Build (flake) vs. runtime (modules) separation
- 322 lines of code removed (build scripts + duplicated functions)
- Better testability: Packages can be tested independently
- Maintainability: Single source of truth for utilities

**For the Project**
- Nix best practices: Proper flake structure, pure derivations
- Upstream-friendly: XOA package could be contributed to nixpkgs
- CI/CD ready: Packages can be built and cached in CI

### 🔧 Implementation Details

**Phase 1 - Package Definitions**
- Created XOA package with yarn2nix using workspace dependencies
- Applied upstream patches (SMB handler, TypeScript generics) in preBuild

[Unreleased]: https://github.com/declarative-dale/nixoa-core/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/declarative-dale/nixoa-core/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/declarative-dale/nixoa-core/compare/540e49a397229cb12301a230c25fe123a42b0eab...v1.2.1
[1.2.0]: https://github.com/declarative-dale/nixoa-core/compare/v1.1.2...540e49a397229cb12301a230c25fe123a42b0eab
[1.1.2]: https://github.com/declarative-dale/nixoa-core/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/declarative-dale/nixoa-core/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/declarative-dale/nixoa-core/compare/v1.0...v1.1.0
