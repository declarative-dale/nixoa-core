# SPDX-License-Identifier: Apache-2.0
# Host-owned NiXOA context values
{...}: {
  hostSystem = "x86_64-linux";
  hostname = "nixo-ce-example";
  deploymentProfile = "physical"; # Options: "physical" or "vm"
  repoDir = "/home/nixoa/nixoa";

  timezone = "Europe/Paris";
  stateVersion = "26.05"; # Do not change after installation

  username = "nixoa";
  gitName = "NiXOA Admin";
  gitEmail = "nixoa@nixoa";
  sshKeys = [
    # Placeholder for template evaluation only. Bootstrap replaces this with real keys.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG9k7m2Yw6S9y4zh7+BTtPlqvGjYH6G+jD/adJzi10BG nixo-ce-template"
  ];

  bootLoader = "systemd-boot"; # Options: "systemd-boot", "grub", or "none"
  efiCanTouchVariables = true;
  grubDevice = "";

  allowedTCPPorts = [
    80
    443
  ];
  allowedUDPPorts = [];

  enableExtras = false;
  shell = null; # null preserves bash by default, zsh when enableExtras is true.
  nixoaMenuAutoStart = false; # Opt in to automatic nixoa-menu startup on SSH login.
  enableXO = true;
  enableXenGuest = false;
  enableXenHardware = false;

  systemPackages = [
    # Examples:
    # "vim"
    # "curl"
  ];

  userPackages = [
    # Examples:
    # "git"
    # "tmux"
  ];

  flatpaks = [];
  flatpakRemotes = [
    {
      name = "flathub";
      location = "https://flathub.org/repo/flathub.flatpakrepo";
    }
  ];

  extraNixosModules = [];
  extraNixosConfig = {};
  extraHomeManagerModules = [];

  immutability.enable = false;

  xoConfig = {}; # Empty uses the structured core default; set xoConfig.toml to override completely.
  xoHttpHost = "0.0.0.0";
  enableTLS = true;
  enableAutoCert = true;

  enableNFS = true;
  enableCIFS = true;
  enableVHD = true;
  mountsDir = "/var/lib/xo/mounts";
  sudoNoPassword = true;
}
