{
  planRunner,
  pkgs,
}: let
  mkCommand = {
    name,
    prefix ? "",
    runtimeInputs ? [],
    source,
  }:
    pkgs.writeShellApplication {
      inherit runtimeInputs;
      name = "nixoa-ci-${name}";
      text = builtins.readFile ./command-preamble.sh + prefix + builtins.readFile source;
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

  spdxSchema = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/spdx/spdx-spec/v2.3/schemas/spdx-schema.json";
    hash = "sha256-I5IIt6woezz12amvI/nWmGOXEQKl4Vh6J6OYtDSQuJs=";
  };

  validatePlan = mkCommand {
    name = "validate-plan";
    prefix = ''
      NIXOA_CI_PLAN_SCHEMA="''${NIXOA_CI_PLAN_SCHEMA:-${./ci-plan.schema.json}}"
      export NIXOA_CI_PLAN_SCHEMA
    '';
    runtimeInputs = commonInputs ++ [pkgs.check-jsonschema];
    source = ./validate-plan.sh;
  };

  classifyPaths = mkCommand {
    name = "classify-paths";
    runtimeInputs = commonInputs;
    source = ./classify-paths.sh;
  };

  commands = {
    boot = mkCommand {
      name = "boot";
      runtimeInputs = commonInputs ++ [pkgs.qemu_kvm];
      source = ./installer-boot.sh;
    };
    build-assets = mkCommand {
      name = "build-assets";
      prefix = ''
        NIXOA_SPDX_SCHEMA="''${NIXOA_SPDX_SCHEMA:-${spdxSchema}}"
        export NIXOA_SPDX_SCHEMA
      '';
      runtimeInputs = commonInputs ++ [pkgs.check-jsonschema planRunner];
      source = ./installer-build-assets.sh;
    };
    build-input = mkCommand {
      name = "build-input";
      runtimeInputs = commonInputs ++ [classifyPaths];
      source = ./build-input.sh;
    };
    repository-audit = mkCommand {
      name = "repository-audit";
      runtimeInputs = commonInputs ++ [planRunner];
      source = ./repository-audit.sh;
    };
    classify = mkCommand {
      name = "classify";
      runtimeInputs = commonInputs ++ [classifyPaths];
      source = ./classify.sh;
    };
    classify-paths = classifyPaths;
    verdict = mkCommand {
      name = "verdict";
      runtimeInputs = commonInputs ++ [validatePlan];
      source = ./verdict.sh;
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
    route = mkCommand {
      name = "route";
      runtimeInputs =
        commonInputs
        ++ [
          commands.classify
          commands.resolve-state
          validatePlan
        ];
      source = ./route.sh;
    };
    publish = mkCommand {
      name = "publish";
      runtimeInputs = commonInputs ++ [pkgs.cachix planRunner];
      source = ./publish.sh;
    };
    queue = mkCommand {
      name = "queue";
      runtimeInputs = commonInputs ++ [commands.trusted-update];
      source = ./queue.sh;
    };
    release-manager = mkCommand {
      name = "release-manager";
      runtimeInputs =
        commonInputs
        ++ [
          pkgs.gzip
          commands.build-input
          commands.release-notes
          commands.release-stage
          commands.release-version
          commands.trusted-update
        ];
      source = ./release-manager.sh;
    };
    release-notes = mkCommand {
      name = "release-notes";
      runtimeInputs = commonInputs;
      source = ./release-notes.sh;
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
    resolve-state = mkCommand {
      name = "resolve-state";
      runtimeInputs = commonInputs ++ [commands.build-input];
      source = ./installer-resolve-state.sh;
    };
    trusted-update = mkCommand {
      name = "trusted-update";
      runtimeInputs = commonInputs;
      source = ./trusted-update.sh;
    };
    update-locks = mkCommand {
      name = "update-locks";
      runtimeInputs = commonInputs;
      source = ./update-locks.sh;
    };
    validate-plan = validatePlan;
  };
in
  commands
