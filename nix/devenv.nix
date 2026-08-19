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

  nixoaCi = command:
    withFlake ''
      nix run --accept-flake-config "$flake_ref#nixoa-ci" -- ${command}
    '';
in {
  packages = import ./devenv-packages.nix {inherit pkgs;};

  tasks = {
    "ci:prepare".exec = nixoaCi "prepare";
    "ci:classify".exec = nixoaCi "classify";

    "ci:check:format" = {
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
    "ci:check:flake" = {
      exec = nixoaCi "check --no-write-lock-file";
      # Reuse is safe only for an identical checkout; every tracked source or
      # documentation change is allowed to invalidate the complete contract.
      execIfModified = ["."];
    };
    "ci:check" = {
      after = [
        "ci:check:flake"
        "ci:check:format"
      ];
      exec = "true";
    };

    "ci:installer:plan".exec = nixoaCi "installer resolve-state";
    "ci:installer:build".exec = nixoaCi "installer build-assets";
    "ci:installer:boot".exec = ''
      ${withFlake ''
        nix shell --accept-flake-config --inputs-from "$flake_ref" nixpkgs#qemu_kvm \
          --command nix run --accept-flake-config "$flake_ref#nixoa-ci" -- \
          installer boot "''${INSTALLER_ISO:-result-installer/iso/nixoa-installer.iso}"
      ''}
    '';
    "ci:publish".exec = nixoaCi "publish";
    "ci:gate".exec = nixoaCi "gate";

    "automation:queue".exec = nixoaCi "queue";
    "automation:update-locks".exec = nixoaCi "locks update";
    "automation:validate-locks".exec = nixoaCi "locks validate";
    "automation:open-lock-update-pr".exec = nixoaCi "open-update-pr flake.lock devenv.lock";

    "release:prepare".exec = nixoaCi "release prepare";
    "release:dispatch".exec = nixoaCi "release dispatch";
    "release:inventory".exec = nixoaCi "release inventory";
    "release:verify".exec = nixoaCi "release verify";
    "release:stage".exec = nixoaCi "release stage";
    "release:draft".exec = nixoaCi "release draft";
    "release:publish".exec = nixoaCi "release publish";
    "release:advance".exec = nixoaCi "release advance";
  };
}
