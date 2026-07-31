# SPDX-License-Identifier: Apache-2.0
{
  lib,
  modulesPath,
  pkgs,
  ...
}: let
  installNixoa = pkgs.writeShellApplication {
    name = "install-nixoa";
    runtimeInputs = with pkgs; [
      coreutils
      dosfstools
      e2fsprogs
      findutils
      git
      gnugrep
      gnused
      gptfdisk
      nixos-install-tools
      parted
      systemd
      util-linux
    ];
    text = builtins.readFile ./install-nixoa.sh;
  };
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  image.baseName = lib.mkForce "nixoa-installer";
  isoImage = {
    volumeID = "NIXOA_INSTALL";
    makeBiosBootable = lib.mkForce false;
    makeUsbBootable = lib.mkForce false;
    grubTheme = null;
  };

  # The upstream minimal installer is intended for interactive recovery on
  # arbitrary hardware. This image has one unattended target: a UEFI Xen VM.
  # Exclude manuals, physical-machine firmware, repair tools, and filesystems
  # that cannot be used by the Packer installation path.
  documentation = {
    enable = lib.mkForce false;
    doc.enable = lib.mkForce false;
    info.enable = lib.mkForce false;
    man.enable = lib.mkForce false;
    nixos.enable = lib.mkForce false;
  };
  hardware = {
    enableAllHardware = lib.mkForce false;
    enableRedistributableFirmware = lib.mkForce false;
    wirelessRegulatoryDatabase = lib.mkForce false;
  };
  boot = {
    initrd.availableKernelModules = lib.mkForce [
      "xen_blkfront"
      "xen_netfront"
    ];
    loader.grub.memtest86.enable = lib.mkForce false;
    supportedFilesystems = lib.mkForce [
      "ext4"
      "vfat"
    ];
    swraid.enable = lib.mkForce false;
  };
  console.packages = lib.mkForce [];
  environment = {
    defaultPackages = lib.mkForce [];
    systemPackages = lib.mkForce [installNixoa];
  };
  programs.git.enable = lib.mkForce false;

  networking = {
    hostName = "nixoa-installer";
    firewall.allowedTCPPorts = [22];
    networkmanager.enable = lib.mkForce false;
    useNetworkd = lib.mkForce true;
  };

  boot.kernelParams = [
    "console=tty0"
    "console=hvc0"
  ];
  boot.zfs.forceImportRoot = false;

  users = {
    mutableUsers = true;
    users.nixoa = {
      isNormalUser = true;
      description = "Temporary NiXOA Packer installer";
      group = "users";
      extraGroups = ["wheel"];
      hashedPassword = "$6$nixoapacker$cWN5T4ysgTquwJsxxFc/iF6rrl8MgYdDV6X4UV8t.MS5ATbQC4aYMsuXkKWsCH9AEBsGEzuEciGpFb6ylMgdU0";
    };
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  security.polkit.enable = lib.mkForce false;

  services = {
    desktopManager.gnome.enable = lib.mkForce false;
    displayManager.enable = lib.mkForce false;
    xserver.enable = lib.mkForce false;
    openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        AllowUsers = ["nixoa"];
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = true;
        PermitEmptyPasswords = false;
        PermitRootLogin = "no";
        PubkeyAuthentication = true;
        X11Forwarding = false;
      };
    };
  };

  systemd.defaultUnit = "multi-user.target";
  systemd.packages = [pkgs.xen-guest-agent];
  systemd.services.xen-guest-agent.wantedBy = ["multi-user.target"];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://install.determinate.systems"
      "https://nixoa.cachix.org"
      "https://xen-orchestra-ce.cachix.org"
      "https://libvhdi-nixpkg.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "nixoa.cachix.org-1:N+GsSSd2yKgj2hx01fMG6Oe7tLfbxEi/V0oZFEB721g="
      "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
      "libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4="
    ];
  };

  system.stateVersion = "26.05";
}
