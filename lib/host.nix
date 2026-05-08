{
  __findFile ? __findFile,
  den,
  inputs,
  lib,
  hostRoot,
  ...
}: let
  contextDefaults = {
    extraHomeManagerModules = [];
    extraNixosConfig = {};
    extraNixosModules = [];
    flatpakRemotes = [
      {
        name = "flathub";
        location = "https://flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    flatpaks = [];
    immutability.enable = false;
    nixoaMenuAutoStart = false;
    shell = null;
    xoConfig = {};
  };

  context = lib.foldl' lib.recursiveUpdate {} [
    contextDefaults
    (import (hostRoot + "/_ctx/settings.nix") {})
    (import (hostRoot + "/_ctx/menu.nix") {})
  ];

  userModule = import (hostRoot + "/_homeManager/default.nix");
  hostImports = den._.import-tree hostRoot;

  mkHostDefinition = hostContext: let
    hostName = hostContext.hostname;
    configuredShell = hostContext.shell or null;
    userShell =
      if configuredShell != null
      then configuredShell
      else if hostContext.enableExtras
      then "zsh"
      else "bash";
  in {
    den.hosts.${hostContext.hostSystem}.${hostName} = {
      instantiate = {modules, ...}:
        inputs.nixpkgs.lib.nixosSystem {
          inherit modules;
          system = hostContext.hostSystem;
          specialArgs = {
            inherit inputs;
            context = hostContext;
          };
        };

      users.${hostContext.username} = {};
    };

    den.aspects.${hostName} = {
      includes = [
        <nixoaCore/appliance>
        hostImports
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

        homeManager = {
          imports = [userModule] ++ (hostContext.extraHomeManagerModules or []);
        };
      };
    };
  };

  vmContext =
    context
    // {
      hostname = "${context.hostname}-vm";
      deploymentProfile = "vm";
      enableXenGuest = true;
      enableXenHardware = true;
      bootLoader = "systemd-boot";
      efiCanTouchVariables = true;
      grubDevice = "";
    };
in
  lib.mkMerge [
    (mkHostDefinition context)
    (mkHostDefinition vmContext)
  ]
