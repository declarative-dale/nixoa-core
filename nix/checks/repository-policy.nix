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

  automationDirectory = builtins.readDir "${source}/nix/automation";
  automationScripts = lib.sort builtins.lessThan (
    builtins.filter
    (name: lib.hasSuffix ".sh" name && automationDirectory.${name} == "regular")
    (builtins.attrNames automationDirectory)
  );
  automationDefinition = read "nix/automation/default.nix";
  automationWrapperRules = map (script: {
    ok = lib.hasInfix "source = ./${script};" automationDefinition;
    message = "nix/automation/${script} must be wrapped by the nixoa-ci package";
  }) automationScripts;

  workflowDirectory = builtins.readDir "${source}/.github/workflows";
  workflowFiles = lib.sort builtins.lessThan (
    builtins.filter
    (name:
      (lib.hasSuffix ".yml" name || lib.hasSuffix ".yaml" name)
      && workflowDirectory.${name} == "regular")
    (builtins.attrNames workflowDirectory)
  );
  workflowRunRules = map (workflow: let
    runLines = builtins.filter
      (line: builtins.match "[[:space:]]*run:.*" line != null)
      (lib.splitString "\n" (read ".github/workflows/${workflow}"));
  in {
    ok = builtins.all
      (line:
        builtins.match
        "[[:space:]]*run: nix run --accept-flake-config .*"
        line
        != null)
      runLines;
    message = ".github/workflows/${workflow} must route every run step through a flake app";
  }) workflowFiles;

  version = lib.removeSuffix "\n" (read "VERSION");
  rules = [
    {
      ok = builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+(-dev\\.[0-9]+)?" version != null;
      message = "VERSION must be a stable or development semantic version";
    }
    (contains ".github/actions/setup-nix/action.yml"
      "DeterminateSystems/determinate-nix-action@61cbfe2efc2d4e7a8a6d56967c3c1058e846c858"
      "CI must pin Determinate Nix to the reviewed revision")
    (excludes ".github/workflows/ci.yml" "magic-nix-cache-action"
      "CI must publish only explicitly planned protected-main closures")
    (excludes ".github/actions/setup-nix/action.yml" "cachix/cachix-action@"
      "CI setup must not implicitly push every realized closure")
    (excludes ".github/actions/setup-nix/action.yml" "actions/cache@"
      "CI must rely on Nix binary caches instead of mutable runner metadata")
    (contains "secretspec.toml" "CACHIX_AUTH_TOKEN"
      "Secretspec must declare the Cachix publishing credential")
    (contains "secretspec.toml" "CACHIX_CACHE_NAME"
      "Secretspec must declare the Cachix repository variable")
    (excludes ".github/workflows/ci.yml" "nixoa-reusable-cache"
      "CI must not retain the superseded closure artifact cache")
    (contains ".github/workflows/ci.yml" "name: CI gate"
      "CI must expose its stable required status")
    (contains ".github/workflows/release.yml" ".#nixoa-ci -- release stage"
      "Release staging must use the flake-packaged automation")
    (contains "nix/automation/release.sh" "--draft"
      "Release publication must pass through a verified draft")
    (contains "nix/automation/release.sh"
      "gh release edit \"$RELEASE_TAG\" --draft=false --latest"
      "Release publication must explicitly publish the verified draft")
    (contains ".github/workflows/release.yml" ".#nixoa-ci -- release prepare"
      "Release version changes must use the protected flake app")
    (contains ".github/workflows/release.yml" "GH_TOKEN: \${{ github.token }}"
      "Release automation must use the repository-scoped GitHub token")
    (contains ".github/workflows/release.yml" "EXPECTED_AUTHOR: github-actions"
      "Release automation must validate GitHub Actions' GraphQL identity")
    (contains "nix/automation/release.sh" "EXPECTED_CHANGE_KIND=version"
      "Release automation must allowlist version-only changes")
    (excludes ".github/workflows/release.yml" "MERGE_QUEUE_TOKEN"
      "Release automation must not require an external merge token")
    (contains ".github/workflows/queue-automation.yml" ".#nixoa-ci -- queue"
      "Scheduled recovery must use the flake-packaged trusted-update command")
    (excludes ".github/workflows/queue-automation.yml" "MERGE_QUEUE_TOKEN"
      "Scheduled recovery must not require an external merge token")
    (contains "nix/automation/trusted-update.sh" "changed_files[0]} == VERSION"
      "Trusted version updates must change only VERSION")
    (contains "nix/automation/trusted-update.sh" "devenv.lock | flake.lock"
      "Trusted lock updates must allowlist only the two Nix lockfiles")
    (excludes ".github/workflows/release.yml" "--generate-notes"
      "Release notes must come from the curated changelog")
    (contains ".github/workflows/update-flake-lock.yml" "cron: \"17 9 * * 3\""
      "Flake input refresh must remain weekly")
    (contains ".github/workflows/update-flake-lock.yml"
      ".#nixoa-ci-update-locks"
      "Input refresh must update the native devenv lock through the flake app")
    (contains ".github/workflows/update-flake-lock.yml"
      ".#nixoa-ci -- locks validate"
      "Input refresh must validate synchronized lockfiles through the flake app")
    (contains ".github/workflows/update-flake-lock.yml" "GH_TOKEN: \${{ github.token }}"
      "Flake input refresh must use the repository-scoped GitHub token")
    (excludes ".github/workflows/update-flake-lock.yml" "MERGE_QUEUE_TOKEN"
      "Flake input refresh must not require an external merge token")
    (excludes ".github/workflows/update-flake-lock.yml" "inputs:"
      "Flake input refresh must not silently omit inputs")
    (contains ".github/dependabot.yml" "package-ecosystem: github-actions"
      "Dependabot must monitor GitHub Actions")
    (contains ".github/dependabot.yml" "package-ecosystem: cargo"
      "Dependabot must monitor Cargo dependencies")
    (contains ".github/workflows/ci.yml" ".#nixoa-ci -- classify"
      "CI change classification must use the flake app")
    (contains ".github/workflows/ci.yml" ".#nixoa-ci -- installer resolve-state"
      "Installer state resolution must use the flake app")
    (contains ".github/workflows/ci.yml" ".#nixoa-ci -- installer build-assets"
      "Installer builds must use the flake app")
    (contains "nix/automation/installer-build-assets.sh" "flake-plan-runner"
      "Installer closure targets must use the shared schema-v2 plan runner")
    (contains "modules/outputs/lib.nix" "mkCiPlan"
      "CI target lists must be exported as pure flake plans")
    (contains ".github/workflows/ci.yml" ".#nixoa-ci -- gate"
      "The stable gate must use the flake-packaged automation")
    (absent ".github/actions/setup-devenv/action.yml"
      "Hosted CI must not install a second devenv orchestration layer")
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
  ] ++ automationWrapperRules ++ workflowRunRules;
  failures = map (rule: rule.message) (builtins.filter (rule: !rule.ok) rules);
in
  assert lib.assertMsg (failures == [])
  ("Repository policy violations:\n- " + lib.concatStringsSep "\n- " failures);
    pkgs.runCommandLocal "nixoa-repository-policy" {} ''
      touch "$out"
    ''
