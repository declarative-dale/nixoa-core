{inputs, ...}: let
  system = "x86_64-linux";
  mkPlan = inputs.xen-orchestra-ce.lib.mkCiPlan;
  target = name: attribute: {inherit name attribute;};
in {
  flake.lib.ciPlans.${system} = {
    validation = mkPlan {
      name = "nixoa-validation";
      targets = [
        (target "metadata" "checks.${system}.metadata")
        (target "nixoa-ci" "checks.${system}.nixoa-ci")
        (target "nxcli" "checks.${system}.nxcli")
        (target "flake-plan-runner" "checks.${system}.flake-plan-runner")
        (target "eval-smoke" "checks.${system}.eval-smoke")
        (target "workflow-policy" "checks.${system}.workflow-policy")
        (target "devenv-contract" "checks.${system}.devenv-contract")
        (target "shell-lint" "checks.${system}.shell-lint")
        (target "automation-fixtures" "checks.${system}.automation-fixtures")
        (target "installer-input-fixtures" "checks.${system}.installer-input-fixtures")
        (target "release-fixtures" "checks.${system}.release-fixtures")
        (target "secretspec-contract" "checks.${system}.secretspec-contract")
        (target "operator-fixtures" "checks.${system}.operator-fixtures")
        (target "repository-policy" "checks.${system}.repository-policy")
        (target "configuration" "checks.${system}.configuration")
        (target "ci-plan-contract" "checks.${system}.ci-plan-contract")
      ];
    };

    installer = mkPlan {
      name = "nixoa-installer";
      targets = [
        (target "toplevel" "nixosConfigurations.nixoa.config.system.build.toplevel")
        ((target "deploy-template" "packages.${system}.deploy-template") // {link = "result-deploy-template";})
        (target "libvhdi" "packages.${system}.libvhdi")
        ((target "metadata" "packages.${system}.metadata") // {link = "result-metadata";})
        ((target "nixoa-menu" "packages.${system}.nixoa-menu") // {link = "result-nixoa-menu";})
        ((target "nxcli" "packages.${system}.nxcli") // {link = "result-nxcli";})
        (target "sbomnix" "packages.${system}.sbomnix")
        (target "xen-orchestra-ce" "packages.${system}.xen-orchestra-ce")
        ((target "installer-iso" "packages.${system}.installer-iso") // {link = "result-installer";})
      ];
    };

    publish = mkPlan {
      name = "nixoa-publish";
      targets = [
        (target "toplevel" "nixosConfigurations.nixoa.config.system.build.toplevel")
        (target "deploy-template" "packages.${system}.deploy-template")
        (target "metadata" "packages.${system}.metadata")
        (target "nixoa-menu" "packages.${system}.nixoa-menu")
        (target "nxcli" "packages.${system}.nxcli")
      ];
    };
  };
}
