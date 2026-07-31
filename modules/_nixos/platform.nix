# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.determinate.nixosModules.default];

  networking = {
    useDHCP = lib.mkDefault false;
    useNetworkd = true;
    networkmanager.enable = false;
    dhcpcd.enable = false;
    firewall = {
      enable = true;
      allowPing = true;
      logRefusedConnections = false;
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks."10-uplink" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_ADDRESS = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
  };

  boot.loader.systemd-boot.configurationLimit = 10;

  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    MaxRetentionSec=30d
    ForwardToConsole=no
    Compress=yes
  '';

  # A system switch must not bounce the system message bus underneath the
  # activation transaction.
  systemd.services = {
    dbus = {
      reloadIfChanged = lib.mkForce false;
      restartIfChanged = lib.mkForce false;
    };
    dbus-broker = {
      reloadIfChanged = lib.mkForce false;
      restartIfChanged = lib.mkForce false;
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    nano
    micro
    wget
    curl
    htop
    btop
    tree
    ncdu
    tmux
    git
    rsync
    lsof
    iotop
    sysstat
    dool
    openssl
    nettools
    nmap
    tcpdump
    dig
    traceroute
  ];

  nix = {
    settings = {
      extra-substituters = [
        "https://xen-orchestra-ce.cachix.org"
        "https://libvhdi-nixpkg.cachix.org"
      ];
      extra-trusted-public-keys = [
        "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
        "libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4="
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}
