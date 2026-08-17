{
  lib,
  pkgs,
  source,
}: let
  read = relative: builtins.readFile "${source}/${relative}";
  contains = relative: needle: message: {
    ok = lib.hasInfix needle (read relative);
    inherit message;
  };
  excludes = relative: needle: message: {
    ok = !lib.hasInfix needle (read relative);
    inherit message;
  };
  absent = relative: message: {
    ok = !builtins.pathExists "${source}/${relative}";
    inherit message;
  };

  version = lib.removeSuffix "\n" (read "VERSION");
  rules = [
    {
      ok = builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+(-dev\\.[0-9]+)?" version != null;
      message = "VERSION must be a stable or development semantic version";
    }
    (contains ".github/workflows/ci.yml"
      "DeterminateSystems/determinate-nix-action@61cbfe2efc2d4e7a8a6d56967c3c1058e846c858"
      "CI must pin Determinate Nix to the reviewed revision")
    (excludes ".github/workflows/ci.yml" "magic-nix-cache-action"
      "CI must use the shared Cachix cache instead of Magic Cache")
    (contains ".github/workflows/ci.yml"
      "cachix/cachix-action@5f2d7c5294214f71b873db4b969586b980625e71"
      "CI must share Nix outputs through Cachix")
    (contains ".github/workflows/ci.yml"
      "cachix/secretspec-action@9a02088c2a41efaf75c0e10e574f0275964bbe7f"
      "CI must resolve cache configuration through pinned Secretspec automation")
    (contains "secretspec.toml" "CACHIX_AUTH_TOKEN"
      "Secretspec must declare the Cachix publishing credential")
    (contains "secretspec.toml" "CACHIX_CACHE_NAME"
      "Secretspec must declare the Cachix repository variable")
    (excludes ".github/workflows/ci.yml" "nixoa-reusable-cache"
      "CI must not retain the superseded closure artifact cache")
    (contains ".github/workflows/ci.yml" "name: CI gate"
      "CI must expose its stable required status")
    (contains ".github/workflows/release.yml" "nix run .#nixoa-ci -- release stage"
      "Release staging must use the consolidated Nix automation app")
    (contains "nix/automation/release.sh" "--draft"
      "Release publication must pass through a verified draft")
    (contains "nix/automation/release.sh"
      "gh release edit \"$RELEASE_TAG\" --draft=false --latest"
      "Release publication must explicitly publish the verified draft")
    (contains ".github/workflows/release.yml" "nix run .#nixoa-ci -- release prepare"
      "Release version changes must use the protected Nix release state machine")
    (contains ".github/workflows/release.yml" "GH_TOKEN: \${{ github.token }}"
      "Release automation must use the repository-scoped GitHub token")
    (contains ".github/workflows/release.yml" "EXPECTED_AUTHOR: github-actions"
      "Release automation must validate GitHub Actions' GraphQL identity")
    (contains "nix/automation/release.sh" "EXPECTED_CHANGE_KIND=version"
      "Release automation must allowlist version-only changes")
    (excludes ".github/workflows/release.yml" "MERGE_QUEUE_TOKEN"
      "Release automation must not require an external merge token")
    (contains ".github/workflows/queue-automation.yml" "nix run .#nixoa-ci -- queue"
      "Scheduled recovery must use the consolidated trusted-update queue")
    (excludes ".github/workflows/queue-automation.yml" "MERGE_QUEUE_TOKEN"
      "Scheduled recovery must not require an external merge token")
    (contains "nix/automation/trusted-update.sh" "changed_files[0]} == VERSION"
      "Trusted version updates must change only VERSION")
    (excludes ".github/workflows/release.yml" "--generate-notes"
      "Release notes must come from the curated changelog")
    (contains ".github/workflows/update-flake-lock.yml" "cron: \"17 9 * * 3\""
      "Flake input refresh must remain weekly")
    (contains ".github/workflows/update-flake-lock.yml"
      "DeterminateSystems/update-flake-lock@834c491b2ece4de0bbd00d85214bb5e83b4da5c6"
      "Flake input refresh must pin the reviewed action revision")
    (contains ".github/workflows/update-flake-lock.yml" "token: \${{ github.token }}"
      "Flake input refresh must use the repository-scoped GitHub token")
    (excludes ".github/workflows/update-flake-lock.yml" "MERGE_QUEUE_TOKEN"
      "Flake input refresh must not require an external merge token")
    (excludes ".github/workflows/update-flake-lock.yml" "inputs:"
      "Flake input refresh must not silently omit inputs")
    (contains ".github/dependabot.yml" "package-ecosystem: github-actions"
      "Dependabot must monitor GitHub Actions")
    (contains ".github/dependabot.yml" "package-ecosystem: cargo"
      "Dependabot must monitor Cargo dependencies")
    (contains ".github/workflows/ci.yml" "nix run .#nixoa-ci -- classify"
      "CI change classification must use the consolidated Nix automation app")
    (contains ".github/workflows/ci.yml" "nix run .#nixoa-ci -- installer resolve-state"
      "Installer state resolution must use the consolidated Nix automation app")
    (contains ".github/workflows/ci.yml" "nix run .#nixoa-ci -- installer build-assets"
      "Installer builds must use the consolidated Nix automation app")
    (excludes ".github/workflows/ci.yml" "./ci/"
      "CI must not call unpackaged repository scripts")
    (excludes ".github/workflows/release.yml" "./ci/"
      "Release automation must not call unpackaged repository scripts")
    (excludes ".github/workflows/queue-automation.yml" "./ci/"
      "Trusted-update recovery must not call unpackaged repository scripts")
    (absent ".github/workflows/cache-nixoa-menu.yml"
      "The superseded package cache workflow must stay removed")
    (absent ".github/workflows/validate.yml"
      "The superseded validation workflow must stay removed")
    (absent ".github/workflows/flakehub-publish-tagged.yml"
      "The obsolete tagged FlakeHub workflow must stay removed")
  ];
  failures = map (rule: rule.message) (builtins.filter (rule: !rule.ok) rules);
in
  assert lib.assertMsg (failures == [])
  ("Repository policy violations:\n- " + lib.concatStringsSep "\n- " failures);
    pkgs.runCommandLocal "nixoa-repository-policy" {} ''
      touch "$out"
    ''
