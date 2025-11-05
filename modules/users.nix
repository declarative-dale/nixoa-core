{ config, pkgs, lib, ... }:

{
  # Primary group for XO service
  users.groups.xo = {};

  # XO service account (runs xo-server and related services)
  users.users.xo = {
    isSystemUser = true;
    description = "Xen Orchestra service account";
    createHome = true;
    group = "xo";
    home = "/var/lib/xo";
    shell = pkgs.shadow + "/bin/nologin";
    
    # Add to fuse group to allow FUSE mounts
    extraGroups = [ "fuse" ];
  };

  # XO admin account: SSH-key login only, sudo-capable
  # This is the human administrator account for managing the XOA system
  users.users.xoa = {
    isNormalUser = true;
    description = "Xen Orchestra Administrator";
    createHome = true;
    home = "/home/xoa";
    shell = pkgs.bashInteractive;
    
    # wheel: sudo access
    # systemd-journal: read system logs
    extraGroups = [ "wheel" "systemd-journal" ];
    
    # Locked password - SSH key authentication only
    hashedPassword = "!";
    
    openssh.authorizedKeys.keys = [
      # Replace with your actual SSH public key(s)
      # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyHere your-email@example.com"
      # Generate with: ssh-keygen -t ed25519 -C "your-email@example.com"
      
      # IMPORTANT: Add your SSH public key here before deploying!
      # Without a valid key, you will not be able to log in.
    ];
  };

  # Optional: Create a fuse group if it doesn't exist
  # (Usually created automatically by programs.fuse.userAllowOther, but explicit is better)
  users.groups.fuse = {};
}
