{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.services.libvhdi;

  version = "20240509";
  
  # Build libvhdi from source
  libvhdi = pkgs.stdenv.mkDerivation {
    pname = "libvhdi";
    inherit version;
    
    src = pkgs.fetchurl {
      url = "https://github.com/libyal/libvhdi/releases/download/${version}/libvhdi-alpha-${version}.tar.gz";
      hash = "sha256-nv6+VKeubPi0kQOjoMN1U/PyLXUmMDplSutZ7KWMzsc=";
    };
    
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
    
    enableParallelBuilding = true;
    
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
    };
  };
in
{
  options.services.libvhdi = {
    enable = mkEnableOption "libvhdi library and tools for VHD image access";

    package = mkOption {
      type = types.package;
      default = libvhdi;
      description = "libvhdi package to use";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    
    # Ensure FUSE support is available
    boot.kernelModules = lib.mkAfter [ "fuse" ];
    programs.fuse.userAllowOther = true;
  };
}