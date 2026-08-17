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
    (contains ".github/workflows/ci.yml"
      "DeterminateSystems/magic-nix-cache-action@908b263ff629f4cc17666315b7fd3ec127c6244d"
      "CI must retain the GitHub-backed Magic Nix Cache")
    (contains ".github/workflows/ci.yml" "use-gha-cache: enabled"
      "Magic Cache must explicitly use GitHub's cache")
    (contains ".github/workflows/ci.yml" "use-flakehub: disabled"
      "CI must not probe the separate FlakeHub Cache service")
    (contains ".github/workflows/ci.yml"
      "cachix/cachix-action@5f2d7c5294214f71b873db4b969586b980625e71"
      "CI must retain public Cachix publishing")
    (contains ".github/workflows/ci.yml" "name: nixoa-reusable-cache"
      "CI must publish the bounded reusable closure cache")
    (contains ".github/workflows/ci.yml" "retention-days: 14"
      "The reusable closure cache must remain short-lived")
    (contains ".github/workflows/ci.yml" "name: CI gate"
      "CI must expose its stable required status")
    (contains ".github/workflows/release.yml" "stage-release-installer.sh"
      "Release staging must partition oversized installers")
    (contains ".github/workflows/release.yml" "--draft"
      "Release publication must pass through a verified draft")
    (contains ".github/workflows/release.yml"
      "gh release edit \"\${RELEASE_TAG}\" --draft=false --latest"
      "Release publication must explicitly publish the verified draft")
    (contains ".github/workflows/release.yml" "./ci/trusted-update.sh"
      "Release version changes must pass through protected main")
    (contains ".github/workflows/release.yml" "GH_TOKEN: \${{ github.token }}"
      "Release automation must use the repository-scoped GitHub token")
    (contains ".github/workflows/release.yml" "EXPECTED_AUTHOR: github-actions"
      "Release automation must validate GitHub Actions' GraphQL identity")
    (contains ".github/workflows/release.yml" "EXPECTED_CHANGE_KIND=version"
      "Release automation must allowlist version-only changes")
    (excludes ".github/workflows/release.yml" "MERGE_QUEUE_TOKEN"
      "Release automation must not require an external merge token")
    (contains ".github/workflows/queue-automation.yml" "EXPECTED_AUTHOR=github-actions"
      "Scheduled recovery must normalize GitHub Actions' bot identity")
    (contains ".github/workflows/queue-automation.yml" "EXPECTED_CHANGE_KIND=version"
      "Scheduled recovery must validate version-only pull requests")
    (excludes ".github/workflows/queue-automation.yml" "MERGE_QUEUE_TOKEN"
      "Scheduled recovery must not require an external merge token")
    (contains "ci/trusted-update.sh" "changed_files[0]} == VERSION"
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
