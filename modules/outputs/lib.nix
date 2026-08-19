{inputs, ...}: let
  system = "x86_64-linux";
  mkPlan = inputs.xen-orchestra-ce.lib.mkCiPlan;
  definitions = builtins.fromJSON (builtins.readFile ../../nix/ci-plans.json);
  validTarget = target:
    target ? name
    && builtins.isString target.name
    && target ? attribute
    && builtins.isString target.attribute
    && (!target ? link || builtins.isString target.link);
  validPlan = plan:
    plan ? name
    && builtins.isString plan.name
    && plan ? targets
    && builtins.isList plan.targets
    && builtins.all validTarget plan.targets;
in {
  flake.lib.ciPlans.${system} = assert builtins.all validPlan (builtins.attrValues definitions);
    builtins.mapAttrs (_: mkPlan) definitions;
}
