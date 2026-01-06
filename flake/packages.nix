# Package definitions
{ inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages = {
        xen-orchestra-ce = pkgs.callPackage ../pkgs/xen-orchestra-ce {
          inherit (inputs) xoSrc;
        };

        libvhdi = pkgs.callPackage ../pkgs/libvhdi {
          inherit (inputs) libvhdiSrc;
        };

        default = config.packages.xen-orchestra-ce;

        metadata = pkgs.stdenv.mkDerivation {
          pname = "nixoa-vm-metadata";
          version = "1.0.0";
          dontUnpack = true;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/doc/nixoa-vm
            echo "NixOA-VM - Xen Orchestra Community Edition on NixOS" > $out/share/doc/nixoa-vm/README
            echo "This is a NixOS configuration flake." >> $out/share/doc/nixoa-vm/README
            echo "See https://codeberg.org/nixoa/nixoa-vm for details." >> $out/share/doc/nixoa-vm/README
          '';
          meta = with pkgs.lib; {
            description = "Experimental Xen Orchestra Community Edition deployment for NixOS homelabs";
            license = licenses.asl20;
            maintainers = [
              {
                name = "Dale Morgan";
                codeberg = "dalemorgan";
              }
            ];
            platforms = platforms.linux;
            homepage = "https://codeberg.org/nixoa/nixoa-vm";
          };
        };
      };
    };
}
