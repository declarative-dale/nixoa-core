{
  description = "XO CE on NixOS modular, variables-first, with update helper";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream Xen Orchestra source (non-flake git repo)
    xoSrc = {
      url = "github:vatesfr/xen-orchestra";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, xoSrc, ... }:
  let
    vars = import ./vars.nix;
    system = vars.system;
    pkgs = import nixpkgs { inherit system; };
    lib = nixpkgs.lib;
  in {
    nixosConfigurations.${vars.hostname} = lib.nixosSystem {
      inherit system;
      modules = [
        ./modules/xoa.nix
        ./modules/storage.nix
        ./modules/libvhdi.nix
        ./modules/updates.nix
        ./modules/boot.nix
        ./hardware-configuration.nix

        # Wire variables into the module options
        ({ config, ... }: {
          networking.hostName = vars.hostname;

          # XOA module configuration
          # Note: xoa.nix creates the admin user - don't duplicate here
          xoa = {
            enable = true;

            admin = {
              user = vars.username;
              sshAuthorizedKeys = vars.sshKeys;
            };

            xo = {
              user      = vars.xoUser;
              group     = vars.xoGroup;
              host      = vars.xoHost;
              port      = vars.xoPort;
              httpsPort = vars.xoHttpsPort;
              ssl = {
                enable = vars.tls.enable;
                dir    = vars.tls.dir;
                cert   = vars.tls.cert;
                key    = vars.tls.key;
              };

              # Provide flake-pinned sources
              srcPath = xoSrc;
              
              # Network isolation during build
              buildIsolation = true;
            };

            storage = {
              nfs.enable  = vars.storage.nfs.enable;
              cifs.enable = vars.storage.cifs.enable;
              mountsDir   = vars.storage.mountsDir;
            };
          };

          # Enable libvhdi support
          services.libvhdi = {
            enable = true;
          };

          # Lock the state version
          system.stateVersion = vars.stateVersion;
          
          # Pass vars to updates module
          updates = vars.updates;

          # Nix flakes UX
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
        })
      ];

      specialArgs = { inherit xoSrc; };
    };

    # Runnable helper: nix run .#update-xo
    apps.${system}.update-xo = {
      type = "app";
      program = toString (pkgs.writeShellApplication {
        name = "update-xo";
        runtimeInputs = [ pkgs.jq pkgs.git pkgs.curl ];
        text = builtins.readFile ./scripts/xoa-update.sh;
      });
      meta = {
        description = "Update the xoSrc input in flake.lock and show new commits.";
      };
    };

    # Development shell
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [ 
        jq 
        git 
        curl 
        nixos-rebuild
      ];
      
      shellHook = ''
        echo "XOA Development Environment"
        echo "Available commands:"
        echo "  nix run .#update-xo                           - Update XO source"
        echo "  sudo nixos-rebuild switch --flake .#${vars.hostname}  - Deploy changes"
        echo ""
      '';
    };
  };
}