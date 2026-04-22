{
  den,
  inputs,
  lib,
  nixoa,
  ...
}:
let
  context = import ./context.nix { inherit lib; };
  mkHost =
    hostContext:
    let
      hostName = hostContext.hostname;
      userShell = if hostContext.enableExtras then "zsh" else "bash";
    in
    {
      den.hosts.${hostContext.hostSystem}.${hostName} = {
        instantiate =
          { modules, ... }:
          inputs.nixpkgs.lib.nixosSystem {
            inherit modules;
            system = hostContext.hostSystem;
            specialArgs = {
              inherit inputs;
              context = hostContext;
            };
          };

        users.${hostContext.username} = { };
      };

      den.aspects.${hostName} = {
        includes = [
          nixoa.appliance
          {
            nixos = {
              imports = [ ./host.nix ];

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "bak";
                extraSpecialArgs = {
                  inherit inputs;
                  context = hostContext;
                };
              };
            };
          }
        ];

        provides.to-users = {
          includes = [
            den._.primary-user
            (den._.user-shell userShell)
          ];

          homeManager = import ./user.nix;
        };
      };
    };
  baseContext = context;
  vmContext = baseContext // {
    hostname = "${baseContext.hostname}-vm";
    deploymentProfile = "vm";
    bootLoader = "none";
    efiCanTouchVariables = false;
    grubDevice = "";
  };
in
lib.mkMerge [
  (mkHost baseContext)
  (lib.optionalAttrs ((baseContext.deploymentProfile or "physical") != "vm") (mkHost vmContext))
]
