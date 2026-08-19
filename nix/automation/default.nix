{
  planRunner,
  lib,
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
      runtimeInputs = commonInputs;
      source = ./installer-boot.sh;
    };
    build-assets = mkCommand {
      name = "build-assets";
      runtimeInputs = commonInputs ++ [planRunner];
      source = ./installer-build-assets.sh;
    };
    build-input = mkCommand {
      name = "build-input";
      runtimeInputs = commonInputs ++ [classifyPaths];
      source = ./build-input.sh;
    };
    classify = mkCommand {
      name = "classify";
      runtimeInputs = commonInputs;
      source = ./classify.sh;
    };
    classify-paths = classifyPaths;
    gate = mkCommand {
      name = "gate";
      runtimeInputs = commonInputs ++ [validatePlan];
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
    prepare = mkCommand {
      name = "prepare";
      runtimeInputs = commonInputs ++ [validatePlan];
      source = ./prepare.sh;
    };
    publish = mkCommand {
      name = "publish";
      runtimeInputs = commonInputs ++ [pkgs.cachix planRunner];
      source = ./publish.sh;
    };
    queue = mkCommand {
      name = "queue";
      runtimeInputs = commonInputs;
      source = ./queue.sh;
    };
    release = mkCommand {
      name = "release";
      runtimeInputs = commonInputs ++ [pkgs.gzip];
      source = ./release.sh;
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
      runtimeInputs = commonInputs;
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
  pkgs.writeShellApplication {
    name = "nixoa-ci";
    runtimeInputs = commonInputs ++ builtins.attrValues commands ++ [planRunner];
    text = builtins.readFile ./cli.sh;
    meta = {
      description = "NiXOA repository CI and release automation";
      license = lib.licenses.asl20;
      mainProgram = "nixoa-ci";
      platforms = ["x86_64-linux"];
    };
    passthru = {inherit commands;};
  }
