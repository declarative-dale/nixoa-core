{
  description = "Xen Orchestra (XO CE) on NixOS 25.05 – FromSource, HTTPS, rootless with sudo mounts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    xoSrc = {
      url = "github:vatesfr/xen-orchestra?rev=fa0202f5b3993643f35f70ce2fd1b5c19b7fa44e";
      flake = false;
    };
    libvhdiSrc = {
      # Release tarball pinned via flake.lock (no manual sha256 needed in modules)
      url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, xoSrc, libvhdiSrc }: let
    system = "x86_64-linux";
    lib    = nixpkgs.lib;
    pkgs   = import nixpkgs { inherit system; };
  in {
    nixosConfigurations.nixoa = lib.nixosSystem {
      inherit system;
      modules = [ 
        ./modules/system.nix 
        ./modules/hardware-configuration.nix 
        ];
      # Provide flake-pinned sources to modules
      specialArgs = { inherit xoSrc libvhdiSrc; };
    };
  };
}
