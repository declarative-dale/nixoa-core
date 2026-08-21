{pkgs, ...}: let
  # GitHub checkouts are Git flakes and exclude ignored devenv state. jj
  # workspaces do not expose a .git directory, so they require an explicit
  # path reference instead of Nix's Git discovery.
  withFlake = command: ''
    flake_ref="path:$DEVENV_ROOT"
    if git -C "$DEVENV_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
      flake_ref="git+file:$DEVENV_ROOT"
    fi
    ${command}
  '';

  runFlakePackage = package: arguments:
    withFlake ''
      NIXOA_SYSTEM_ROOT="$DEVENV_ROOT" \
        nix run --accept-flake-config "$flake_ref#${package}" -- ${arguments}
    '';
in {
  packages = import ./devenv-packages.nix {inherit pkgs;};

  tasks = {
    "ci:route".exec = runFlakePackage "nixoa-ci-route" "";
    "ci:classify".exec = runFlakePackage "nixoa-ci-classify" "";

    "ci:repository-audit:format" = {
      exec = withFlake ''
        cd "$DEVENV_ROOT"
        if git rev-parse --show-toplevel >/dev/null 2>&1; then
          mapfile -d $'\0' -t nix_files < <(git ls-files -z -- '*.nix')
        else
          # jj workspaces do not expose .git. Ignore generated environment
          # state while retaining a useful local formatting check.
          mapfile -d $'\0' -t nix_files < <(
            find . \( -path './.devenv' -o -path './.direnv' \) -prune \
              -o -type f -name '*.nix' -print0
          )
        fi
        system="$(nix eval --impure --raw --expr builtins.currentSystem)"
        nix run --accept-flake-config "$flake_ref#formatter.$system" -- \
          --check "''${nix_files[@]}"
      '';
      execIfModified = [
        "*.nix"
        "**/*.nix"
      ];
    };
    "ci:repository-audit:flake" = {
      exec = runFlakePackage "nixoa-ci-repository-audit" "--no-write-lock-file";
      # Reuse is safe only for an identical checkout; every tracked source or
      # documentation change is allowed to invalidate the complete contract.
      execIfModified = ["."];
    };
    "ci:repository-audit" = {
      after = [
        "ci:repository-audit:flake"
        "ci:repository-audit:format"
      ];
    };

    "ci:installer:state".exec = runFlakePackage "nixoa-ci-resolve-state" "";
    "ci:installer:build".exec = runFlakePackage "nixoa-ci-build-assets" "";
    "ci:installer:boot".exec = runFlakePackage "nixoa-ci-boot" ''
      "''${INSTALLER_ISO:-result-installer/iso/nixoa-installer.iso}"
    '';
    "ci:publish".exec = runFlakePackage "nixoa-ci-publish" "";
    "ci:verdict".exec = runFlakePackage "nixoa-ci-verdict" "";

    "automation:queue".exec = runFlakePackage "nixoa-ci-queue" "";
    "automation:update-locks".exec = runFlakePackage "nixoa-ci-update-locks" "";
    "automation:validate-locks".exec = runFlakePackage "nixoa-ci-lock-validate" "";
    "automation:open-lock-update-pr".exec =
      runFlakePackage "nixoa-ci-open-update-pr" "flake.lock devenv.lock";

    "release:prepare".exec = runFlakePackage "nixoa-ci-release-manager" "prepare";
    "release:dispatch".exec = runFlakePackage "nixoa-ci-release-manager" "dispatch";
    "release:inventory".exec = runFlakePackage "nixoa-ci-release-manager" "inventory";
    "release:verify".exec = runFlakePackage "nixoa-ci-release-manager" "verify";
    "release:stage".exec = runFlakePackage "nixoa-ci-release-manager" "stage";
    "release:draft".exec = runFlakePackage "nixoa-ci-release-manager" "draft";
    "release:publish".exec = runFlakePackage "nixoa-ci-release-manager" "publish";
    "release:advance".exec = runFlakePackage "nixoa-ci-release-manager" "advance";
  };
}
