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
      name = "maestro-ci-${name}";
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
      MAESTRO_CI_PLAN_SCHEMA="''${MAESTRO_CI_PLAN_SCHEMA:-${./qualification-plan.schema.json}}"
      export MAESTRO_CI_PLAN_SCHEMA
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
    boot-media = mkCommand {
      name = "boot-media";
      runtimeInputs = commonInputs ++ [pkgs.qemu_kvm];
      source = ./boot-media.sh;
    };
    qualification-assets = mkCommand {
      name = "qualification-assets";
      prefix = ''
        MAESTRO_SPDX_SCHEMA="''${MAESTRO_SPDX_SCHEMA:-${spdxSchema}}"
        export MAESTRO_SPDX_SCHEMA
      '';
      runtimeInputs = commonInputs ++ [pkgs.check-jsonschema planRunner];
      source = ./qualification-assets.sh;
    };
    qualification-inputs = mkCommand {
      name = "qualification-inputs";
      runtimeInputs = commonInputs;
      source = ./qualification-inputs.sh;
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
      runtimeInputs = with pkgs; [
        bash
        coreutils
        jq
      ];
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
          commands.resolve-qualification
          validatePlan
        ];
      source = ./route-plan.sh;
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
          commands.qualification-inputs
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
    resolve-qualification = mkCommand {
      name = "resolve-qualification";
      runtimeInputs = commonInputs ++ [commands.qualification-inputs];
      source = ./qualification-resolve.sh;
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
