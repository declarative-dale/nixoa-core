{
  den,
  inputs,
  ...
}: {
  den.aspects.operator = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
    ];

    nixos.imports = [../_nixos/operator.nix];
    homeManager.imports = [(inputs.import-tree ../_homeManager)];
  };
}
