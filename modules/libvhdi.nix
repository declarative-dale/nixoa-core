{ lib, pkgs, libvhdiSrc ? null, ... }:
let
  version = "20240509";
  
  src = if libvhdiSrc != null then libvhdiSrc else pkgs.fetchurl {
    url = "https://github.com/libyal/libvhdi/releases/download/${version}/libvhdi-alpha-${version}.tar.gz";
    hash = "sha256-nv6+VKeubPi0kQOjoMN1U/PyLXUmMDplSutZ7KWMzsc=";
  };

  libvhdi = pkgs.stdenv.mkDerivation {
    pname = "libvhdi";
    inherit version src;
    
    nativeBuildInputs = with pkgs; [ 
      autoreconfHook 
      pkg-config 
    ];
    
    buildInputs = with pkgs; [ 
      fuse 
      zlib 
    ];
    
    configureFlags = [
      "--enable-python=no"
      "--enable-static=no"
      "--with-libfuse=yes"
    ];
    
    # Enable parallel building for faster compilation
    enableParallelBuilding = true;
    
    # Ensure proper permissions
    postInstall = ''
      # Verify the library was built
      if [ ! -f "$out/lib/libvhdi.so" ]; then
        echo "Error: libvhdi.so not found after build" >&2
        exit 1
      fi
    '';
    
    meta = with lib; {
      description = "Library and tools to access the Virtual Hard Disk (VHD) image format";
      longDescription = ''
        libvhdi is a library to access the Virtual Hard Disk (VHD) image format.
        It supports both fixed and dynamic VHD images, and can handle snapshots.
        This library is used by Xen Orchestra for accessing VHD disk images.
      '';
      homepage = "https://github.com/libyal/libvhdi";
      license = licenses.lgpl3Plus;
      platforms = platforms.linux;
      maintainers = [ ];
    };
  };
in
{
  # No options: always present on the system when XOA is enabled
  config = {
    environment.systemPackages = [ libvhdi ];
    
    # Ensure FUSE support is available
    boot.kernelModules = lib.mkAfter [ "fuse" ];
  };
}