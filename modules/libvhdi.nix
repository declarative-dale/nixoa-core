{ config, pkgs, lib, libvhdiSrc ? null, ... }:

let
  version = "20240509";

  # Official source distribution package (contains vendored libyal deps + configure)
  src = if libvhdiSrc != null then libvhdiSrc else pkgs.fetchurl {
    url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
    hash = "sha256-nv6+VKeubPi0kQOjoMN1U/PyLXUmMDplSutZ7KWMzsc=";
  };

  libvhdi = pkgs.stdenv.mkDerivation {
    pname = "libvhdi";
    inherit version src;

    nativeBuildInputs = with pkgs; [
      pkg-config
      autoreconfHook
    ];

    buildInputs = with pkgs; [
      fuse          # FUSE2 for vhdimount
      fuse3         # FUSE3 support
      zlib          # Compression support
    ];

    # Enable FUSE-based vhdimount tool
    configureFlags = [
      "--enable-shared"
      "--with-libfuse=yes"
      "--enable-multi-threading=yes"
    ];

    # Ensure tools are built and installed
    enableParallelBuilding = true;

    meta = with lib; {
      description = "Library and tools to access VHD/VHDX image formats";
      longDescription = ''
        libvhdi provides:
        - vhdiinfo: Display information about VHD/VHDX files
        - vhdimount: FUSE-based tool to mount VHD/VHDX as a filesystem
        
        Used by Xen Orchestra for backup restore and disk inspection operations.
      '';
      homepage = "https://github.com/libyal/libvhdi";
      license = licenses.lgpl3Plus;
      platforms = platforms.linux;
      maintainers = [ ];
    };
  };
in
{
  # Install libvhdi library and tools system-wide
  environment.systemPackages = [ libvhdi ];

  # Enable FUSE user mounts with allow_other/allow_root options
  # Required for the xo user to mount VHD files via vhdimount
  programs.fuse.userAllowOther = lib.mkDefault true;

  # Ensure FUSE kernel module is loaded
  boot.kernelModules = [ "fuse" ];

  # Additional system configuration for VHD operations
  systemd.tmpfiles.rules = [
    # Ensure /dev/fuse has appropriate permissions
    "c /dev/fuse 0666 root root - 10:229"
  ];
}
