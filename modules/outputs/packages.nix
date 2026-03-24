{
  inputs,
  lib,
  ...
}:
let
  systems = [ "x86_64-linux" ];
in
{
  flake.packages = lib.genAttrs systems (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in
    {
      xen-orchestra-ce = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;
      libvhdi = inputs.xen-orchestra-ce.packages.${system}.libvhdi;
      default = inputs.xen-orchestra-ce.packages.${system}.xen-orchestra-ce;

      metadata = pkgs.stdenv.mkDerivation {
        pname = "nixoa-core-metadata";
        version = "2.0.0";
        dontUnpack = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/share/doc/nixoa-core
          echo "NiXOA Core - Xen Orchestra Community Edition on NixOS" > $out/share/doc/nixoa-core/README
          echo "This is a NixOS module library flake." >> $out/share/doc/nixoa-core/README
          echo "See https://codeberg.org/NiXOA/core for details." >> $out/share/doc/nixoa-core/README
        '';
        meta = with pkgs.lib; {
          description = "Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";
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
