#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nixoa-ci COMMAND [ARGS...]

Commands:
  classify                        Classify the current GitHub event
  classify-paths                  Classify newline-delimited changed paths
  gate                            Enforce the conditional GitHub CI graph
  installer build-input           Print the immutable installer input digest
  installer resolve-state         Resolve reusable GitHub installer state
  installer build-assets          Build the installer, packages, and SBOMs
  installer boot [ISO]            Boot-test an installer ISO
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

command="${1:-help}"
case "$command" in
  classify)
    shift
    exec "$NIXOA_CI_CLASSIFY" "$@"
    ;;
  classify-paths)
    shift
    exec "$NIXOA_CI_CLASSIFY_PATHS" "$@"
    ;;
  gate)
    shift
    exec "$NIXOA_CI_GATE" "$@"
    ;;
  installer)
    subcommand="${2:-}"
    shift 2 || true
    case "$subcommand" in
      build-input) exec "$NIXOA_CI_BUILD_INPUT" "$@" ;;
      resolve-state) exec "$NIXOA_CI_RESOLVE_STATE" "$@" ;;
      build-assets) exec "$NIXOA_CI_BUILD_ASSETS" "$@" ;;
      boot) exec "$NIXOA_CI_BOOT" "$@" ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  locks)
    subcommand="${2:-}"
    shift 2 || true
    case "$subcommand" in
      validate) exec "$NIXOA_CI_LOCK_VALIDATE" "$@" ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  open-update-pr)
    shift
    exec "$NIXOA_CI_OPEN_UPDATE_PR" "$@"
    ;;
  publish)
    shift
    exec "$NIXOA_CI_PUBLISH" "$@"
    ;;
  release)
    subcommand="${2:-}"
    shift 2 || true
    case "$subcommand" in
      version) exec "$NIXOA_CI_RELEASE_VERSION" "$@" ;;
      notes) exec "$NIXOA_CI_RELEASE_NOTES" "$@" ;;
      split) exec "$NIXOA_CI_RELEASE_STAGE" "$@" ;;
      prepare|dispatch|inventory|verify|stage|draft|publish|advance)
        exec "$NIXOA_CI_RELEASE" "$subcommand" "$@"
        ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  trusted-update)
    shift
    exec "$NIXOA_CI_TRUSTED_UPDATE" "$@"
    ;;
  queue)
    shift
    exec "$NIXOA_CI_QUEUE" "$@"
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
    exec "$NIXOA_CI_PLAN_RUNNER" \
      --flake "$flake_ref" \
      --plan "$NIXOA_CI_VALIDATION_PLAN"
    ;;
  plan)
    shift
    plan="${1:-$NIXOA_CI_VALIDATION_PLAN}"
    if (($# > 0)); then
      shift
    fi
    exec "$NIXOA_CI_PLAN_RUNNER" \
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
