{ config, lib, pkgs, libvhdiSrc ? null, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.services.libvhdi;

  version = "20240509";
  
  # Use flake-provided source or fetch it
  src = if libvhdiSrc != null then libvhdiSrc else pkgs.fetchurl {
    url = "https://github.com/libyal/libvhdi/releases/download/${version}/libvhdi-alpha-${version}.tar.gz";
    hash = "sha256-nv6+VKeubPi0kQOjoMN1U/PyLXUmMDplSutZ7KWMzsc=";
  };
  
  # Build libvhdi from source with full feature support
  libvhdi = pkgs.stdenv.mkDerivation {
    pname = "libvhdi";
    inherit version src;
    
    nativeBuildInputs = with pkgs; [ 
      autoreconfHook 
      pkg-config 
    ];
    
    buildInputs = with pkgs; [ 
      fuse          # FUSE2 for vhdimount
      fuse3         # FUSE3 support
      zlib          # Compression support
    ];
    
    configureFlags = [
      "--enable-shared"
      "--enable-static=no"
      "--enable-python=no"
      "--with-libfuse=yes"
      "--enable-multi-threading=yes"
      "--enable-wide-character-type"
    ];
    
    enableParallelBuilding = true;
    
    postInstall = ''
      # Verify the library and tools were built
      if [ ! -f "$out/lib/libvhdi.so" ]; then
        echo "Error: libvhdi.so not found after build" >&2
        exit 1
      fi
      
      if [ ! -f "$out/bin/vhdimount" ]; then
        echo "Error: vhdimount tool not found after build" >&2
        exit 1
      fi
      
      if [ ! -f "$out/bin/vhdiinfo" ]; then
        echo "Error: vhdiinfo tool not found after build" >&2
        exit 1
      fi
      
      echo "libvhdi tools installed:"
      ls -la "$out/bin/"
    '';
    
    meta = with lib; {
      description = "Library and tools to access the Virtual Hard Disk (VHD) image format";
      longDescription = ''
        libvhdi provides:
        - vhdiinfo: Display information about VHD/VHDX files
        - vhdimount: FUSE-based tool to mount VHD/VHDX as a filesystem
        - vhdiexport: Export VHD data to raw format
        
        Used by Xen Orchestra for backup restore and disk inspection operations.
        This package supports both VHD (Virtual Hard Disk) and VHDX (Virtual Hard Disk v2) formats.
      '';
      homepage = "https://github.com/libyal/libvhdi";
      license = licenses.lgpl3Plus;
      platforms = platforms.linux;
      maintainers = [ ];
    };
  };
in
{
  options.services.libvhdi = {
    enable = mkEnableOption "libvhdi library and tools for VHD/VHDX image access";

    package = mkOption {
      type = types.package;
      default = libvhdi;
      defaultText = lib.literalExpression "libvhdi";
      description = "libvhdi package to use";
    };
  };

  config = mkIf cfg.enable {
    # Install libvhdi library and tools system-wide
    environment.systemPackages = [ cfg.package ];
    
    # Enable FUSE user mounts with allow_other/allow_root options
    # Required for the xo user to mount VHD files via vhdimount
    programs.fuse.userAllowOther = lib.mkDefault true;
    
    # Ensure FUSE kernel module is loaded
    boot.kernelModules = lib.mkAfter [ "fuse" ];
    
    # Additional system configuration for VHD operations
    systemd.tmpfiles.rules = [
      # Ensure /dev/fuse has appropriate permissions
      # Note: Mode 0666 allows all users to access FUSE
      "c /dev/fuse 0666 root root - 10:229"
    ];
    
    # Create a wrapper script for safe VHD mounting
    environment.etc."xo/vhd-mount-helper.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        # Safe VHD mount helper for XO
        set -euo pipefail
        
        if [ $# -lt 2 ]; then
          echo "Usage: $0 <vhd-file> <mount-point>" >&2
          exit 1
        fi
        
        VHD_FILE="$1"
        MOUNT_POINT="$2"
        
        # Validate VHD file exists
        if [ ! -f "$VHD_FILE" ]; then
          echo "Error: VHD file not found: $VHD_FILE" >&2
          exit 1
        fi
        
        # Create mount point if needed
        mkdir -p "$MOUNT_POINT"
        
        # Mount with FUSE
        exec ${cfg.package}/bin/vhdimount -o allow_other "$VHD_FILE" "$MOUNT_POINT"
      '';
    };
  };
}
