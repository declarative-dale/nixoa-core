{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.nixoa = {
    instantiate = {modules, ...}:
      inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        inherit modules;
        specialArgs = {inherit inputs;};
      };
    users.nixoa = {};
  };

  den.aspects.nixoa.includes = [
    den.aspects.platform
    den.aspects.xcp-ng
    den.aspects.xo
    den.aspects.operator
    {
      nixos.imports = [../host];
    }
  ];
}
