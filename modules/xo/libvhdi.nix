# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, nixoaPackages, ... }:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.services.libvhdi;

  # Reference the packaged libvhdi from flake
  libvhdiPackage = nixoaPackages.libvhdi;
in
{
  options.services.libvhdi = {
    enable = mkEnableOption "libvhdi library and tools for VHD/VHDX image access";

    package = mkOption {
      type = types.package;
      default = libvhdiPackage;
      defaultText = lib.literalExpression "nixoaPackages.libvhdi";
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
  };
}
