{
  description = "Xen Orchestra (XO CE) on NixOS 25.05 — sources@5.111.1, HTTPS, rootless with sudo mounts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    lib    = nixpkgs.lib;
    pkgs   = import nixpkgs { inherit system; };
  in {
    # Expose modules for reuse
    nixosModules = {
      xen-orchestra = import ./modules/xen-orchestra.nix;
      users         = import ./modules/users.nix;
      updates       = import ./modules/updates.nix;
    };

    # Example host config; adjust to your host and add your hardware-configuration.nix
    nixosConfigurations.xoa = lib.nixosSystem {
      inherit system;
      specialArgs = {
        # XO 5.111.1 build commit (maps to xo-server 5.111.1 / xo-web 5.114.0)
        # Ref: forum report linking version to commit afadc8f…
        xoCommit = "afadc8f95adf741611d1f298dfe77cbf1f895231";
      };
      modules = [
        ./modules/xen-orchestra.nix
        ./modules/users.nix
        ./modules/updates.nix
        # Include your host's hardware-configuration.nix here
        # ./hardware-configuration.nix
      ];
    };
  };
}
