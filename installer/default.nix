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
  isoImage.volumeID = "NIXOA_INSTALL";

  networking.hostName = "nixoa-installer";
  networking.firewall.allowedTCPPorts = [22];

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

  services.openssh = {
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

  systemd.packages = [pkgs.xen-guest-agent];
  systemd.services.xen-guest-agent.wantedBy = ["multi-user.target"];

  environment.systemPackages = [installNixoa];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://cache.flakehub.com"
      "https://xen-orchestra-ce.cachix.org"
      "https://libvhdi-nixpkg.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "xen-orchestra-ce.cachix.org-1:WAOajkFLXWTaFiwMbLidlGa5kWB7Icu29eJnYbeMG7E="
      "libvhdi-nixpkg.cachix.org-1:HvYHKZcfczn2nGfCmd7F21E/MDZrlaXtN3p9mWAZT/4="
    ];
  };

  system.stateVersion = "26.05";
}
