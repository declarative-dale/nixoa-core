{ config, pkgs, lib, ... }:

let
  # Pick a known release; you can bump this later
  version = "20240509";

  # Official source distribution package (contains vendored libyal deps + configure)
  # See: https://github.com/libyal/libvhdi/releases (tags like libvhdi-alpha-20240509)
  src = pkgs.fetchurl {
    url = "https://github.com/libyal/libvhdi/releases/download/20240509/libvhdi-alpha-20240509.tar.gz";
    # Run once to get the real hash:
    #   nix-prefetch-url $url
    hash = "sha256-nv6+VKeubPi0kQOjoMN1U/PyLXUmMDplSutZ7KWMzsc=";
  };

  libvhdi = pkgs.stdenv.mkDerivation {
    pname = "libvhdi";
    inherit version src;

    # For ./configure, pkg-config checks, etc.  (configure script is already produced in the source tarball)
    nativeBuildInputs = [ pkgs.pkg-config ];

    # Build deps: FUSE enables vhdimount; zlib is a common dependency in libyal stacks.
    buildInputs = [
      pkgs.fuse          # FUSE2 headers/libs so vhdimount is built
      pkgs.zlib
    ];

    # Make sure the FUSE-based vhdimount is compiled
    configureFlags = [ "--with-libfuse=yes" ];

    # Standard Autotools phases are auto-detected by mkDerivation
    # (configure -> make -> make install)

    meta = with lib; {
      description = "Library and tools to access the VHD/VHDX image formats (vhdiinfo, vhdimount)";
      homepage    = "https://github.com/libyal/libvhdi";
      license     = licenses.lgpl3Plus;
      platforms   = platforms.linux;
      maintainers = [ ];
    };
  };
in
{
  #### NixOS module part ####
  # Put the library + tools in PATH system-wide.
  environment.systemPackages = [ libvhdi ];

  # Optional: allow non-root users to use 'allow_other/allow_root' with FUSE.
  # If you only run vhdimount as root or via sudo (e.g. from XO), you might not need this.
  programs.fuse.userAllowOther = lib.mkDefault false;
}
