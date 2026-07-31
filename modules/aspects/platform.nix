{
  den,
  inputs,
  ...
}: {
  den.aspects.platform.nixos = {
    imports = [../_nixos/platform.nix];
  };
}
