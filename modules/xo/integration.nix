# SPDX-License-Identifier: Apache-2.0
# XO integration: bridges systemSettings to XO modules and service configuration

{ config, pkgs, lib, systemSettings ? {}, userSettings ? {}, nixoaUtils, ... }:

let
  inherit (nixoaUtils) getOption;

  # Extract commonly used values
  username = getOption systemSettings ["username"] "xoa";
  sshKeys = getOption systemSettings ["sshKeys"] [];
  xoServiceUser = getOption systemSettings ["xo" "service" "user"] "xo";
  xoServiceGroup = getOption systemSettings ["xo" "service" "group"] "xo";
  xoHost = getOption systemSettings ["xo" "host"] "0.0.0.0";
  xoPort = getOption systemSettings ["xo" "port"] 80;
  xoHttpsPort = getOption systemSettings ["xo" "httpsPort"] 443;
  xoTlsEnable = getOption systemSettings ["xo" "tls" "enable"] true;
  xoTlsRedirect = getOption systemSettings ["xo" "tls" "redirectToHttps"] true;
  xoTlsAutoGen = getOption systemSettings ["xo" "tls" "autoGenerate"] true;
  xoTlsDir = getOption systemSettings ["xo" "tls" "dir"] "/etc/ssl/xo";
  xoTlsCert = getOption systemSettings ["xo" "tls" "cert"] "/etc/ssl/xo/certificate.pem";
  xoTlsKey = getOption systemSettings ["xo" "tls" "key"] "/etc/ssl/xo/key.pem";
  storageNfsEnable = getOption systemSettings ["storage" "nfs" "enable"] true;
  storageCifsEnable = getOption systemSettings ["storage" "cifs" "enable"] true;
  storageVhdEnable = getOption systemSettings ["storage" "vhd" "enable"] true;
  storageMountsDir = getOption systemSettings ["storage" "mountsDir"] "/var/lib/xo/mounts";
  updatesConfig = getOption systemSettings ["updates"] {};
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
