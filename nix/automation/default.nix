{
  lib,
  pkgs,
}: let
  mkCommand = {
    name,
    runtimeInputs ? [],
    source,
  }:
    pkgs.writeShellApplication {
      inherit runtimeInputs;
      name = "nixoa-ci-${name}";
      text = ''
        if [ -n "''${NIXOA_CI_PATH_PREFIX:-}" ]; then
          export PATH="$NIXOA_CI_PATH_PREFIX:$PATH"
        fi
        ${builtins.readFile source}
      '';
    };

  commonInputs = with pkgs; [
    bash
    coreutils
    findutils
    git
    gh
    gnugrep
    gnused
    jq
    nix
  ];
  installerPolicy = import ./installer-policy.nix;

  buildInput = pkgs.writeShellApplication {
    name = "nixoa-ci-build-input";
    runtimeInputs = commonInputs;
    text = ''
      repo_root="''${NIXOA_SYSTEM_ROOT:-}"
      if [ -z "$repo_root" ]; then
        repo_root=$(git rev-parse --show-toplevel)
      fi
      {
        printf '%s\0' 'nixoa-installer-state-v3'
        git -C "$repo_root" ls-files -s -z -- \
          ${lib.escapeShellArgs installerPolicy.buildInputPaths}
      } | sha256sum | cut -d' ' -f1
    '';
  };

  classifyPaths = pkgs.writeShellApplication {
    name = "nixoa-ci-classify-paths";
    runtimeInputs = commonInputs;
    text = ''
      required=false
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
          .github/workflows/ci.yml)
            required=true
            break
            ;;
          ${lib.concatStringsSep "|" installerPolicy.ignoredChangePatterns})
            ;;
          *)
            required=true
            break
            ;;
        esac
      done
      printf '%s\n' "$required"
    '';
  };

  commands = {
    boot = mkCommand {
      name = "boot";
      runtimeInputs = commonInputs;
      source = ./installer-boot.sh;
    };
    build-assets = mkCommand {
      name = "build-assets";
      runtimeInputs = commonInputs;
      source = ./installer-build-assets.sh;
    };
    build-input = buildInput;
    classify = mkCommand {
      name = "classify";
      runtimeInputs = commonInputs;
      source = ./classify.sh;
    };
    classify-paths = classifyPaths;
    gate = mkCommand {
      name = "gate";
      runtimeInputs = commonInputs;
      source = ./gate.sh;
    };
    lock-validate = mkCommand {
      name = "lock-validate";
      runtimeInputs = commonInputs;
      source = ./lock-validate.sh;
    };
    publish = pkgs.writeShellApplication {
      name = "nixoa-ci-publish";
      runtimeInputs = commonInputs;
      text = ''
        cd "''${NIXOA_SYSTEM_ROOT:-$(git rev-parse --show-toplevel)}"
        nix build --accept-flake-config .#deploy-template -o result-deploy-template
        nix build --accept-flake-config .#metadata -o result-metadata
        nix build --accept-flake-config .#nixoa-menu -o result-nixoa-menu
        nix build --accept-flake-config .#nxcli -o result-nxcli
      '';
    };
    release-notes = mkCommand {
      name = "release-notes";
      runtimeInputs = commonInputs;
      source = ./release-notes.sh;
    };
    release = mkCommand {
      name = "release";
      runtimeInputs = commonInputs ++ [pkgs.gzip];
      source = ./release.sh;
    };
    release-stage = mkCommand {
      name = "release-stage";
      runtimeInputs = commonInputs;
      source = ./release-split.sh;
    };
    release-version = mkCommand {
      name = "release-version";
      runtimeInputs = commonInputs;
      source = ./release-version.sh;
    };
    queue = mkCommand {
      name = "queue";
      # GitHub-hosted runners provide gh; leaving it injectable keeps the
      # network-facing behavior fixture-testable with a fake executable.
      runtimeInputs = commonInputs;
      source = ./queue.sh;
    };
    resolve-state = mkCommand {
      name = "resolve-state";
      runtimeInputs = commonInputs;
      source = ./installer-resolve-state.sh;
    };
    trusted-update = mkCommand {
      name = "trusted-update";
      runtimeInputs = commonInputs;
      source = ./trusted-update.sh;
    };
  };

  commandPath = command: lib.getExe commands.${command};
in
  pkgs.writeShellApplication {
    name = "nixoa-ci";
    runtimeInputs = commonInputs;
    text = ''
      repo_root="''${NIXOA_SYSTEM_ROOT:-}"
      if [ -z "$repo_root" ]; then
        if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
          repo_root="$git_root"
        else
          repo_root="$PWD"
        fi
      fi
      export NIXOA_SYSTEM_ROOT="$repo_root"
      export NIXOA_CI_BUILD_INPUT=${commandPath "build-input"}
      export NIXOA_CI_CLASSIFY_PATHS=${commandPath "classify-paths"}
      export NIXOA_CI_LOCK_VALIDATE=${commandPath "lock-validate"}
      export NIXOA_CI_RELEASE_NOTES=${commandPath "release-notes"}
      export NIXOA_CI_RELEASE_STAGE=${commandPath "release-stage"}
      export NIXOA_CI_RELEASE_VERSION=${commandPath "release-version"}
      export NIXOA_CI_TRUSTED_UPDATE=${commandPath "trusted-update"}

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
      EOF
      }

      command="''${1:-help}"
      case "$command" in
        classify)
          shift
          exec ${commandPath "classify"} "$@"
          ;;
        classify-paths)
          shift
          exec ${commandPath "classify-paths"} "$@"
          ;;
        gate)
          shift
          exec ${commandPath "gate"} "$@"
          ;;
        installer)
          subcommand="''${2:-}"
          shift 2 || true
          case "$subcommand" in
            build-input) exec ${commandPath "build-input"} "$@" ;;
            resolve-state) exec ${commandPath "resolve-state"} "$@" ;;
            build-assets) exec ${commandPath "build-assets"} "$@" ;;
            boot) exec ${commandPath "boot"} "$@" ;;
            *) usage >&2; exit 2 ;;
          esac
          ;;
        locks)
          subcommand="''${2:-}"
          shift 2 || true
          case "$subcommand" in
            validate) exec ${commandPath "lock-validate"} "$@" ;;
            *) usage >&2; exit 2 ;;
          esac
          ;;
        publish)
          shift
          exec ${commandPath "publish"} "$@"
          ;;
        release)
          subcommand="''${2:-}"
          shift 2 || true
          case "$subcommand" in
            version) exec ${commandPath "release-version"} "$@" ;;
            notes) exec ${commandPath "release-notes"} "$@" ;;
            split) exec ${commandPath "release-stage"} "$@" ;;
            prepare|dispatch|inventory|verify|stage|draft|publish|advance)
              exec ${commandPath "release"} "$subcommand" "$@"
              ;;
            *) usage >&2; exit 2 ;;
          esac
          ;;
        trusted-update)
          shift
          exec ${commandPath "trusted-update"} "$@"
          ;;
        queue)
          shift
          exec ${commandPath "queue"} "$@"
          ;;
        check)
          shift
          cd "$repo_root"
          flake_ref="path:$repo_root"
          if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
            flake_ref="git+file:$repo_root"
          fi
          exec nix flake check --accept-flake-config --print-build-logs \
            "$flake_ref" "$@"
          ;;
        help|-h|--help)
          usage
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '';
    meta = {
      description = "NiXOA repository CI and release automation";
      license = lib.licenses.asl20;
      mainProgram = "nixoa-ci";
      platforms = ["x86_64-linux"];
    };
    passthru = {inherit commands;};
  }
