{ lib, pkgs, libvhdiSrc ? null, ... }:
let
  version = "20240509";
  src = if libvhdiSrc != null then libvhdiSrc else pkgs.fetchurl {
    url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
    hash = "sha256-nv6+VKeubPi0kQOjoMN1U/PyLXUmMDplSutZ7KWMzsc=";
  };

  libvhdi = pkgs.stdenv.mkDerivation {
    pname = "libvhdi";
    inherit version src;
    nativeBuildInputs = with pkgs; [ autoreconfHook pkg-config ];
    buildInputs = with pkgs; [ fuse zlib libtool ];
    configureFlags = [ "--enable-python=no" "--enable-static=no" ];
  };
in
{
  # No options: always present on the system
  config = {
    environment.systemPackages = [ libvhdi ];
  };
}
