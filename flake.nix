{
  description = "Xen Orchestra (XO CE) on NixOS 25.05 — FromSource, HTTPS, rootless with sudo mounts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    xoSrc = {
      url = "github:vatesfr/xen-orchestra?rev=2dd451a7d933f27e550fac673029d8ab79aba70d";
      flake = false;
    };
    libvhdiSrc = {
      # Release tarball pinned via flake.lock (no manual sha256 needed in modules)
      url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
      flake = false;
    };  };

  outputs = { self, nixpkgs, xoSrc, libvhdiSrc }: let
    system = "x86_64-linux";
    lib    = nixpkgs.lib;
    pkgs   = import nixpkgs { inherit system; };
  in {
    nixosConfigurations.xoa = lib.nixosSystem {
      inherit system;
      modules = [ ./modules/system.nix ];
      # Provide flake-pinned sources to modules
      specialArgs = { inherit xoSrc libvhdiSrc; };
    };
  };
}
