{
  den,
  inputs,
  lib,
  ...
}:
let
  systems = lib.unique ([ "x86_64-linux" ] ++ builtins.attrNames den.hosts);
  automation = import ../../host/_automation/default.nix { };
  selectedVmHost = automation.vmHost or null;
  selectedVmOutput = if selectedVmHost == null then null else "${selectedVmHost}-vm";
in
{
  flake.packages = lib.genAttrs systems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      nixoaMenu = pkgs.callPackage ../../pkgs/nixoa-menu/package.nix { };
      nhPackages = den.lib.nh.denPackages {
        fromFlake = true;
        fromPath = ".";
      } pkgs;
      vmAliasPackage =
        if selectedVmOutput != null && nhPackages ? "${selectedVmOutput}" then
          nhPackages.${selectedVmOutput}
        else
          null;
    in
    nhPackages
    // lib.optionalAttrs (vmAliasPackage != null) {
      vm = vmAliasPackage;
    }
    // {
      xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
      libvhdi = inputs.xen-orchestra-ce.packages.${system}.libvhdi;
      default = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      nixoa-menu = nixoaMenu;
    }
    // {
      metadata = pkgs.stdenv.mkDerivation {
        pname = "nixoa-core-metadata";
        version = "3.1.0";
        dontUnpack = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/share/doc/nixoa-core
          echo "NiXOA - Xen Orchestra Community Edition on NixOS" > $out/share/doc/nixoa-core/README
          echo "This is a Den-native appliance flake with host templates under host/." >> $out/share/doc/nixoa-core/README
          echo "See https://codeberg.org/NiXOA/core for details." >> $out/share/doc/nixoa-core/README
        '';
        meta = with pkgs.lib; {
          description = "Den-native Xen Orchestra Community Edition appliance flake for NixOS homelabs";
          homepage = "https://codeberg.org/NiXOA/core";
          license = licenses.asl20;
          maintainers = [
            {
              name = "Dale Morgan";
              codeberg = "dalemorgan";
            }
          ];
          platforms = platforms.linux;
        };
      };
    }
  );
}
