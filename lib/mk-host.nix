{
  __findFile ? __findFile,
  den,
  inputs,
  lib,
  hostRoot,
  ...
}:
let
  context = lib.foldl' lib.recursiveUpdate { } [
    (import (hostRoot + "/_ctx/settings.nix") { })
    (import (hostRoot + "/_ctx/menu.nix") { })
  ];

  userModule = import (hostRoot + "/_homeManager/default.nix");

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
          <nixoaCore/appliance>
          (den._.import-tree hostRoot)
          {
            nixos.home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "bak";
              extraSpecialArgs = {
                inherit inputs;
                context = hostContext;
              };
            };
          }
        ];

        provides.to-users = {
          includes = [
            den._.primary-user
            (den._.user-shell userShell)
          ];

          homeManager = userModule;
        };
      };
    };

  vmContext = context // {
    hostname = "${context.hostname}-vm";
    deploymentProfile = "vm";
    bootLoader = "none";
    efiCanTouchVariables = false;
    grubDevice = "";
  };
in
lib.mkMerge [
  (mkHost context)
  (lib.optionalAttrs ((context.deploymentProfile or "physical") != "vm") (mkHost vmContext))
]
