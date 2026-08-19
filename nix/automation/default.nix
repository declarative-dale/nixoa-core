{
  planRunner,
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
  installerPolicy = builtins.fromJSON (builtins.readFile ./installer-policy.json);

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
      runtimeInputs = commonInputs ++ [planRunner];
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
    open-update-pr = mkCommand {
      name = "open-update-pr";
      runtimeInputs = commonInputs;
      source = ./open-update-pr.sh;
    };
    publish = pkgs.writeShellApplication {
      name = "nixoa-ci-publish";
      runtimeInputs = commonInputs ++ [pkgs.cachix planRunner];
      text = ''
        cd "''${NIXOA_SYSTEM_ROOT:-$(git rev-parse --show-toplevel)}"
        manifest=$(mktemp)
        trap 'rm -f "$manifest"' EXIT
        ${lib.getExe planRunner} \
          --flake . \
          --plan lib.ciPlans.${pkgs.stdenv.hostPlatform.system}.publish \
          --manifest "$manifest"
        jq -r '.results[].outputs[]' "$manifest" |
          cachix push "$CACHIX_CACHE_NAME"
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
  system = pkgs.stdenv.hostPlatform.system;
in
  pkgs.writeShellApplication {
    name = "nixoa-ci";
    runtimeInputs = commonInputs;
    text = ''
      export NIXOA_CI_BOOT=${commandPath "boot"}
      export NIXOA_CI_BUILD_ASSETS=${commandPath "build-assets"}
      export NIXOA_CI_BUILD_INPUT=${commandPath "build-input"}
      export NIXOA_CI_CLASSIFY=${commandPath "classify"}
      export NIXOA_CI_CLASSIFY_PATHS=${commandPath "classify-paths"}
      export NIXOA_CI_GATE=${commandPath "gate"}
      export NIXOA_CI_LOCK_VALIDATE=${commandPath "lock-validate"}
      export NIXOA_CI_OPEN_UPDATE_PR=${commandPath "open-update-pr"}
      export NIXOA_CI_PLAN_RUNNER=${lib.getExe planRunner}
      export NIXOA_CI_PUBLISH=${commandPath "publish"}
      export NIXOA_CI_QUEUE=${commandPath "queue"}
      export NIXOA_CI_RELEASE=${commandPath "release"}
      export NIXOA_CI_RELEASE_NOTES=${commandPath "release-notes"}
      export NIXOA_CI_RELEASE_STAGE=${commandPath "release-stage"}
      export NIXOA_CI_RELEASE_VERSION=${commandPath "release-version"}
      export NIXOA_CI_RESOLVE_STATE=${commandPath "resolve-state"}
      export NIXOA_CI_TRUSTED_UPDATE=${commandPath "trusted-update"}
      export NIXOA_CI_VALIDATION_PLAN=lib.ciPlans.${system}.validation
      ${builtins.readFile ./cli.sh}
    '';
    meta = {
      description = "NiXOA repository CI and release automation";
      license = lib.licenses.asl20;
      mainProgram = "nixoa-ci";
      platforms = ["x86_64-linux"];
    };
    passthru = {inherit commands;};
  }
