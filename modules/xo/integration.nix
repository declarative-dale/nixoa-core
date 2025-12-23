# SPDX-License-Identifier: Apache-2.0
# XO integration: bridges systemSettings to XO modules and service configuration

{ config, pkgs, lib, systemSettings ? {}, userSettings ? {}, ... }:

let
  # Safe attribute access with defaults
  get = path: default:
    let
      getValue = cfg: pathList:
        if pathList == []
        then cfg
        else if builtins.isAttrs cfg && builtins.hasAttr (builtins.head pathList) cfg
        then getValue cfg.${builtins.head pathList} (builtins.tail pathList)
        else null;
      result = getValue systemSettings path;
    in
      if result == null then default else result;

  # Extract commonly used values
  username = get ["username"] "xoa";
  sshKeys = get ["sshKeys"] [];
  xoServiceUser = get ["xo" "service" "user"] "xo";
  xoServiceGroup = get ["xo" "service" "group"] "xo";
  xoHost = get ["xo" "host"] "0.0.0.0";
  xoPort = get ["xo" "port"] 80;
  xoHttpsPort = get ["xo" "httpsPort"] 443;
  xoTlsEnable = get ["xo" "tls" "enable"] true;
  xoTlsRedirect = get ["xo" "tls" "redirectToHttps"] true;
  xoTlsAutoGen = get ["xo" "tls" "autoGenerate"] true;
  xoTlsDir = get ["xo" "tls" "dir"] "/etc/ssl/xo";
  xoTlsCert = get ["xo" "tls" "cert"] "/etc/ssl/xo/certificate.pem";
  xoTlsKey = get ["xo" "tls" "key"] "/etc/ssl/xo/key.pem";
  storageNfsEnable = get ["storage" "nfs" "enable"] true;
  storageCifsEnable = get ["storage" "cifs" "enable"] true;
  storageVhdEnable = get ["storage" "vhd" "enable"] true;
  storageMountsDir = get ["storage" "mountsDir"] "/var/lib/xo/mounts";
  updatesConfig = get ["updates"] {};
in
{
  # ============================================================================
  # XEN ORCHESTRA SERVICE CONFIGURATION
  # ============================================================================

  # Main XOA module configuration
  # Configure XO service based on systemSettings
  xoa = {
    enable = true;

    admin = {
      user = username;
      sshAuthorizedKeys = sshKeys;
    };

    xo = {
      user = xoServiceUser;
      group = xoServiceGroup;
      host = xoHost;
      port = xoPort;
      httpsPort = xoHttpsPort;

      ssl = {
        enable = xoTlsEnable;
        redirectToHttps = xoTlsRedirect;
        dir = xoTlsDir;
        cert = xoTlsCert;
        key = xoTlsKey;
      };

      # Network isolation during build
      buildIsolation = true;
    };

    # Automatic TLS certificate generation
    autocert = {
      enable = xoTlsAutoGen;
    };

    storage = {
      nfs.enable = storageNfsEnable;
      cifs.enable = storageCifsEnable;
      vhd.enable = storageVhdEnable;
      mountsDir = storageMountsDir;
    };
  };

  # xo-server capabilities - needs to run sudo for mounting operations
  systemd.services.xo-server.serviceConfig = {
    # Capabilities needed for normal operation
    AmbientCapabilities = lib.mkForce [
      "CAP_NET_BIND_SERVICE"  # Bind to ports 80/443
      "CAP_SETUID"            # Required for sudo to switch users
      "CAP_SETGID"            # Required for sudo to switch groups
    ];
    # Don't restrict CapabilityBoundingSet - mount.cifs needs unrestricted caps
    # The service itself only gets the AmbientCapabilities, but child processes
    # (like sudo->mount->mount.cifs) can gain more via setuid
    CapabilityBoundingSet = lib.mkForce [ ];

    # Ensure NoNewPrivileges is disabled so sudo/setuid wrappers work
    NoNewPrivileges = lib.mkForce false;
  };

  # Pass update configuration to updates module
  updates = updatesConfig;

  # Pass extras configuration to extras module
  xoa.extras = userSettings.extras or {};
}
