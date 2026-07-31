# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  # NiXOA is always an XCP-ng guest. Disk and filesystem declarations are
  # intentionally left entirely to host/hardware-configuration.nix.
  systemd.packages = [pkgs.xen-guest-agent];
  systemd.services.xen-guest-agent.wantedBy = ["multi-user.target"];
  environment.systemPackages = [pkgs.cloud-init];

  # Xen Orchestra supplies a NoCloud config drive when one is requested for a
  # clone. Cloud-init is intentionally limited to instance identity and SSH
  # key provisioning: NixOS remains authoritative for users, networking,
  # filesystems, packages, and services.
  services.cloud-init = {
    enable = true;
    network.enable = false;
    settings = {
      datasource_list = [
        "NoCloud"
        "None"
      ];
      preserve_hostname = true;
      manage_etc_hosts = false;
      disable_root = true;
      ssh_pwauth = false;
      ssh_deletekeys = false;
      ssh_genkeytypes = [
        "ed25519"
        "rsa"
      ];
      users = ["default"];
      system_info.default_user = {
        name = "nixoa";
        gecos = "NiXOA operator";
        homedir = "/home/nixoa";
        groups = [
          "users"
          "wheel"
          "systemd-journal"
        ];
        sudo = null;
        shell = "/run/current-system/sw/bin/bash";
        lock_passwd = true;
      };

      # The appliance never delegates partitioning, filesystem growth,
      # networking, package installation, or arbitrary scripts to cloud-init.
      cloud_init_modules = ["seed_random"];
      cloud_config_modules = ["ssh"];
      cloud_final_modules = [
        "ssh-authkey-fingerprints"
        "keys-to-console"
        "final-message"
      ];
    };
  };

  # Do not expose SSH until NoCloud keys have been applied.
  systemd.services.sshd = {
    wants = ["cloud-config.service"];
    after = ["cloud-config.service"];
  };
}
