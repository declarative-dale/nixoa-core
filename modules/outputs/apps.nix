{
  inputs,
  lib,
  ...
}: let
  systems = ["x86_64-linux"];
  mkNxcliApp = pkgs: nxcli: {
    appName,
    args,
    description,
  }: {
    type = "app";
    program = toString (
      pkgs.writeShellScript appName ''
        set -euo pipefail
        exec ${nxcli}/bin/nxcli ${lib.escapeShellArgs args} "$@"
      ''
    );
    meta.description = description;
  };
in {
  flake.apps = lib.genAttrs systems (
    system: let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package:
          lib.getName package == "packer";
      };
      nxcli = inputs.self.packages.${system}.nxcli;
      nixoaMenu = inputs.self.packages.${system}.nixoa-menu;
      nixoaCi = inputs.self.packages.${system}.nixoa-ci;
      nixoaCiInstallerBoot = inputs.self.packages.${system}.nixoa-ci-installer-boot;
      nixoaCiUpdateLocks = inputs.self.packages.${system}.nixoa-ci-update-locks;
      planRunner = inputs.self.packages.${system}.flake-plan-runner;
      bootstrap = inputs.self.packages.${system}.bootstrap;
      buildTemplate = inputs.self.packages.${system}.build-template;
      deployTemplate = inputs.self.packages.${system}.deploy-template;
      devenv = inputs.devenv.packages.${system}.devenv;
      nxcliApp = mkNxcliApp pkgs nxcli;
    in {
      devenv = {
        type = "app";
        program = lib.getExe devenv;
        meta.description = "Run the pinned native devenv task and shell interface";
      };

      nxcli = {
        type = "app";
        program = "${nxcli}/bin/nxcli";
        meta.description = "Canonical NiXOA operator CLI";
      };

      apply = nxcliApp {
        appName = "nixoa-apply";
        args = ["apply"];
        description = "Apply a NiXOA host configuration through nxcli";
      };

      bootstrap = {
        type = "app";
        program = lib.getExe bootstrap;
        meta.description = "Bootstrap the fixed nixoa appliance checkout";
      };

      build-template = {
        type = "app";
        program = lib.getExe buildTemplate;
        meta.description = "Build a native NiXOA XCP-ng template with Packer";
      };

      deploy-template = {
        type = "app";
        program = lib.getExe deployTemplate;
        meta.description = "Build and deploy a native NiXOA XCP-ng template";
      };

      commit = nxcliApp {
        appName = "nixoa-commit";
        args = ["commit"];
        description = "Commit NiXOA repository changes through nxcli";
      };

      diff = nxcliApp {
        appName = "nixoa-diff";
        args = ["diff"];
        description = "Show NiXOA repository changes through nxcli";
      };

      history = nxcliApp {
        appName = "nixoa-history";
        args = ["history"];
        description = "Show NiXOA repository history through nxcli";
      };

      menu = {
        type = "app";
        program = "${nixoaMenu}/bin/nixoa-menu";
        meta.description = "Launch the NiXOA SSH administration TUI";
      };

      nixoa-ci = {
        type = "app";
        program = lib.getExe nixoaCi;
        meta.description = "Run NiXOA repository CI and release automation";
      };

      nixoa-ci-installer-boot = {
        type = "app";
        program = lib.getExe nixoaCiInstallerBoot;
        meta.description = "Boot-test the installer with flake-provided QEMU";
      };

      nixoa-ci-update-locks = {
        type = "app";
        program = lib.getExe nixoaCiUpdateLocks;
        meta.description = "Refresh native devenv inputs with pinned tooling";
      };

      run-ci-plan = {
        type = "app";
        program = lib.getExe planRunner;
        meta.description = "Validate and execute a pure flake CI plan";
      };
    }
  );
}
