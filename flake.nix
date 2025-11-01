{
  description = "Xen Orchestra (XO CE) on NixOS 25.05 — sources@5.111.1, HTTPS, rootless with sudo mounts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    lib    = nixpkgs.lib;
    pkgs   = import nixpkgs { inherit system; };

    # Auto-import every .nix under ./modules (assumes only modules live there)
    modulesDir   = ./modules;
    moduleNames  = builtins.attrNames (builtins.readDir modulesDir);
    moduleFiles  = lib.filter (n: lib.hasSuffix ".nix" n) moduleNames;
    moduleFiles' = lib.sort builtins.lessThan moduleFiles;
    autoModules  = map (n: modulesDir + ("/" + n)) moduleFiles';
  in {
    # Optional: expose submodules for reuse
    nixosModules = lib.listToAttrs (map (p: { name = builtins.baseNameOf p; value = import p; }) autoModules);

    nixosConfigurations.xoa = lib.nixosSystem {
      inherit system;
      modules = autoModules;
    };
  };
}
