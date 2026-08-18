{inputs, ...}: let
  system = "x86_64-linux";
  mkPlan = inputs.xen-orchestra-ce.lib.mkFlakeAttributePlan;
in {
  flake.lib.ciPlans.${system} = {
    validation = mkPlan {
      name = "nixoa-validation";
      targets = [
        "checks.${system}.metadata"
        "checks.${system}.nixoa-ci"
        "checks.${system}.nxcli"
        "checks.${system}.flake-attribute-validator"
        "checks.${system}.eval-smoke"
        "checks.${system}.workflow-policy"
        "checks.${system}.devenv-contract"
        "checks.${system}.shell-lint"
        "checks.${system}.automation-fixtures"
        "checks.${system}.installer-input-fixtures"
        "checks.${system}.release-fixtures"
        "checks.${system}.secretspec-contract"
        "checks.${system}.operator-fixtures"
        "checks.${system}.repository-policy"
        "checks.${system}.configuration"
        "checks.${system}.ci-plan-contract"
      ];
    };

    installer = mkPlan {
      name = "nixoa-installer";
      targets = [
        "nixosConfigurations.nixoa.config.system.build.toplevel"
        "packages.${system}.deploy-template"
        "packages.${system}.libvhdi"
        "packages.${system}.metadata"
        "packages.${system}.nixoa-menu"
        "packages.${system}.nxcli"
        "packages.${system}.sbomnix"
        "packages.${system}.xen-orchestra-ce"
      ];
    };
  };
}
