#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixoa-ci COMMAND [ARGS...]

Commands:
  prepare                         Emit the authoritative downstream CI plan
  classify                        Classify the current GitHub event
  classify-paths                  Classify newline-delimited changed paths
  gate                            Enforce the conditional GitHub CI graph
  installer build-input           Print the immutable installer input digest
  installer resolve-state         Resolve reusable GitHub installer state
  installer build-assets          Build the installer, packages, and SBOMs
  installer boot [ISO]            Boot-test an installer ISO
  locks update                     Refresh native and flake input pins
  locks validate [LOCKS...]        Verify shared native and flake input pins
  open-update-pr PATH...           Publish an allowlisted automation update
  publish                          Build reusable rolling outputs
  release version LAST BUMP        Select a semantic release version from stdin
  release notes VERSION [FILE]     Extract curated notes from CHANGELOG.md
  release split SOURCE TARGET DIR  Split a release installer for GitHub assets
  release prepare|dispatch         Prepare a protected release and its tested artifacts
  release inventory|verify         Validate immutable release inputs and attestations
  release stage|draft|publish      Stage and publish the verified release
  release advance                  Start the next protected development version
  trusted-update                   Validate and enqueue an allowlisted automation PR
  queue                            Validate and enqueue all trusted automation PRs
  check                            Run the complete flake check
  plan [PLAN]                      Validate and execute one pure CI plan
EOF
}

repo_root="${NIXOA_SYSTEM_ROOT:-}"
if [ -z "$repo_root" ]; then
  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    repo_root="$git_root"
  else
    repo_root="$PWD"
  fi
fi
export NIXOA_SYSTEM_ROOT="$repo_root"
if [[ -n ${NIXOA_CI_PATH_PREFIX:-} ]]; then
  export PATH="$NIXOA_CI_PATH_PREFIX:$PATH"
fi

plan_runner=${NIXOA_CI_PLAN_RUNNER:-flake-plan-runner}
validation_plan=${NIXOA_CI_VALIDATION_PLAN:-lib.ciPlans.x86_64-linux.validation}

command="${1:-help}"
case "$command" in
  prepare)
    shift
    exec nixoa-ci-prepare "$@"
    ;;
  classify)
    shift
    exec nixoa-ci-classify "$@"
    ;;
  classify-paths)
    shift
    exec nixoa-ci-classify-paths "$@"
    ;;
  gate)
    shift
    exec nixoa-ci-gate "$@"
    ;;
  installer)
    subcommand="${2:-}"
    shift 2 || true
    case "$subcommand" in
      build-input) exec nixoa-ci-build-input "$@" ;;
      resolve-state) exec nixoa-ci-resolve-state "$@" ;;
      build-assets) exec nixoa-ci-build-assets "$@" ;;
      boot) exec nixoa-ci-boot "$@" ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  locks)
    subcommand="${2:-}"
    shift 2 || true
    case "$subcommand" in
      update) exec nixoa-ci-update-locks "$@" ;;
      validate) exec nixoa-ci-lock-validate "$@" ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  open-update-pr)
    shift
    exec nixoa-ci-open-update-pr "$@"
    ;;
  publish)
    shift
    exec nixoa-ci-publish "$@"
    ;;
  release)
    subcommand="${2:-}"
    shift 2 || true
    case "$subcommand" in
      version) exec nixoa-ci-release-version "$@" ;;
      notes) exec nixoa-ci-release-notes "$@" ;;
      split) exec nixoa-ci-release-stage "$@" ;;
      prepare|dispatch|inventory|verify|stage|draft|publish|advance)
        exec nixoa-ci-release "$subcommand" "$@"
        ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  trusted-update)
    shift
    exec nixoa-ci-trusted-update "$@"
    ;;
  queue)
    shift
    exec nixoa-ci-queue "$@"
    ;;
  check)
    shift
    cd "$repo_root"
    flake_ref="path:$repo_root"
    if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
      flake_ref="git+file:$repo_root"
    fi
    nix flake check --accept-flake-config --no-build --print-build-logs \
      "$flake_ref" "$@"
    exec "$plan_runner" \
      --flake "$flake_ref" \
      --plan "$validation_plan"
    ;;
  plan)
    shift
    plan="${1:-$validation_plan}"
    if (($# > 0)); then
      shift
    fi
    exec "$plan_runner" \
      --flake "$repo_root" \
      --plan "$plan" \
      "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
