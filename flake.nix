{
  description = "Xen Orchestra (XO CE) on NixOS 25.05 — FromSource, HTTPS, rootless with sudo mounts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    xoSrc = {
      url = "github:vatesfr/xen-orchestra?rev=2dd451a7d933f27e550fac673029d8ab79aba70d";
      flake = false;
    };
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
      # Host settings that *use* the module
      ({ config, pkgs, ... }: {
        xoa.xo = {
          enable   = true;

          # Use the flake-pinned source path
          srcPath  = xoSrc;

          # If srcPath is set, you do NOT set srcRev/srcHash here.
          # appDir   = "/var/lib/xo/app";          # defaults ok
          # cacheDir = "/var/cache/xo/yarn-cache"; # defaults ok
        };
      })
    };
  };
}
