# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
in {
  imports = [
    ./service.nix
    ./tls.nix
    ./storage.nix
  ];

  options.nixoa.xo = {
    enable = lib.mkEnableOption "Xen Orchestra";
    package = mkOption {
      type = types.package;
      default = inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce;
      defaultText = lib.literalExpression "inputs.xen-orchestra-ce.packages.x86_64-linux.xen-orchestra-ce";
      description = "Xen Orchestra package to run.";
    };
    user = mkOption {
      type = types.str;
      default = "xo";
      description = "System user that runs Xen Orchestra.";
    };
    group = mkOption {
      type = types.str;
      default = "xo";
      description = "Primary group for the Xen Orchestra service user.";
    };
    home = mkOption {
      type = types.str;
      default = "/var/lib/xo";
      description = "XO service home directory.";
    };
    cacheDir = mkOption {
      type = types.str;
      default = "${config.nixoa.xo.home}/.cache";
      description = "XO cache directory.";
    };
    dataDir = mkOption {
      type = types.str;
      default = "${config.nixoa.xo.home}/data";
      description = "XO data directory.";
    };
    tempDir = mkOption {
      type = types.str;
      default = "${config.nixoa.xo.home}/tmp";
      description = "XO temporary directory.";
    };
    httpHost = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address used in automatically generated certificates.";
    };
    config.toml = mkOption {
      type = types.lines;
      default = "";
      description = "Optional complete xo-server TOML configuration.";
    };
    extraServerEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for xo-server.";
    };
    redis = {
      maxmemory = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "256mb";
        description = "Optional Valkey memory limit for XO.";
      };
      maxmemoryPolicy = mkOption {
        type = types.str;
        default = "noeviction";
        description = "Valkey eviction policy for the XO database.";
      };
    };
    tls = {
      enable = lib.mkEnableOption "TLS for XO";
      autoCert = lib.mkEnableOption "automatic self-signed XO certificates";
      dir = mkOption {
        type = types.str;
        default = "/etc/ssl/xo";
        description = "XO TLS directory.";
      };
      cert = mkOption {
        type = types.str;
        default = "${config.nixoa.xo.tls.dir}/certificate.pem";
        description = "XO TLS certificate path.";
      };
      key = mkOption {
        type = types.str;
        default = "${config.nixoa.xo.tls.dir}/key.pem";
        description = "XO TLS key path.";
      };
    };
    storage = {
      enableNFS = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NFS remote storage support.";
      };
      enableCIFS = mkOption {
        type = types.bool;
        default = true;
        description = "Enable CIFS remote storage support.";
      };
      enableVHD = mkOption {
        type = types.bool;
        default = true;
        description = "Enable VHD/VHDX access through libvhdi.";
      };
      mountsDir = mkOption {
        type = types.str;
        default = "/var/lib/xo/mounts";
        description = "Root directory for XO-managed mounts.";
      };
      libvhdiPackage = mkOption {
        type = types.package;
        default = inputs.xen-orchestra-ce.packages.x86_64-linux.libvhdi;
        description = "libvhdi implementation used by XO.";
      };
    };
  };
}
