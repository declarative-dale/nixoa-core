{
  inputs,
  ...
}:
{
  flake.modules.nixos.appliance = {
    imports = [ inputs.self.modules.nixos.nixoaCore ];
  };
}
