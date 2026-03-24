# SPDX-License-Identifier: Apache-2.0
# SSH service configuration
{
  vars,
  ...
}:
{
  config = {
    services.openssh = {
      enable = true;
      openFirewall = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
        AllowUsers = [ vars.username ];

        X11Forwarding = false;
        PermitEmptyPasswords = false;
        Protocol = 2;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
      };

      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
    };
  };
}
