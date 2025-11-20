# vars.nix - User Configuration
# Edit this file to customize your Xen Orchestra deployment
{
  # ============================================================================
  # REQUIRED SETTINGS
  # ============================================================================
  
  # System architecture (usually don't change)
  system = "x86_64-linux";
  
  # Hostname for this NixOS system
  hostname = "xoa";
  
  # Admin username for SSH access (will have sudo rights)
  username = "xoa";
  
  # SSH public keys for admin user (at least one required)
  # Generate with: ssh-keygen -t ed25519
  sshKeys = [
    # "ssh-ed25519 AAAAC3... user@host"
  ];
  
  # ============================================================================
  # XEN ORCHESTRA SETTINGS
  # ============================================================================
  
  # Network binding (0.0.0.0 = all interfaces, 127.0.0.1 = localhost only)
  xoHost = "0.0.0.0";
  
  # Networking / firewall (XO web ports + VNC/RDP for console access)
  networking.firewall.allowedTCPPorts = [ 80 443 3389 5900 8012 ];
  
  # HTTP and HTTPS ports
  xoPort = 80;
  xoHttpsPort = 443;
  
  # TLS/SSL configuration
  tls = {
    enable = true;                          # Auto-generate self-signed certificates
    dir = "/etc/ssl/xo";                    # Certificate storage directory
    cert = "/etc/ssl/xo/certificate.pem";   # Certificate file path
    key = "/etc/ssl/xo/key.pem";            # Private key file path
  };
  
  # ============================================================================
  # STORAGE & MOUNTING
  # ============================================================================
  
  storage = {
    nfs.enable = true;                      # Enable NFS remote storage
    cifs.enable = true;                     # Enable CIFS/SMB remote storage
    mountsDir = "/var/lib/xo/mounts";       # Where to mount remote storage
  };
  
  # ============================================================================
  # AUTOMATED UPDATES
  # ============================================================================
  
  updates = {
    # Location of this flake repository
    # IMPORTANT: Must match where you cloned the repo
    # Common choices:
    #   - "/etc/nixos/nixoa" (system-wide, recommended)
    #   - "~/nixoa" (user directory)
    repoDir = "~/nixoa";
    
    # Files to protect from git operations (never overwrite these)
    protectPaths = [ "vars.nix" "hardware-configuration.nix" ];
    
    # --- Monitoring & Notifications ---
    monitoring = {
      notifyOnSuccess = false;              # Send notifications for successful updates too
      
      # Email notifications (requires working mail setup)
      email = {
        enable = false;                     # Enable: true | Disable: false
        to = "admin@example.com";           # Email address for alerts
      };
      
      # ntfy.sh push notifications (mobile/desktop)
      ntfy = {
        enable = false;                     # Enable: true | Disable: false
        server = "https://ntfy.sh";         # Use public server or self-hosted
        topic = "xoa-updates-myserver";     # Unique topic name (make it random!)
      };
      
      # Generic webhook (Discord, Slack, custom)
      webhook = {
        enable = false;                     # Enable: true | Disable: false
        url = "";                           # Webhook URL
      };
    };
    
    # --- Garbage Collection ---
    # Automatically clean up old system generations
    gc = {
      enable = false;                       # Enable: true | Disable: false
      schedule = "Sun 04:00";               # When to run (systemd calendar format)
      keepGenerations = 7;                  # How many generations to keep
    };
    
    # --- Flake Self-Update ---
    # Pull latest changes from the Codeberg repository
    flake = {
      enable = false;                       # Enable: true | Disable: false
      schedule = "Sun 04:00";               # When to check for updates
      remoteUrl = "https://codeberg.org/dalemorgan/declarative-xoa-ce.git";
      branch = "main";                      # Branch to track
      autoRebuild = false;                  # Rebuild system after update?
    };
    
    # --- NixOS Updates ---
    # Update nixpkgs (system packages) and rebuild
    nixpkgs = {
      enable = false;                       # Enable: true | Disable: false
      schedule = "Mon 04:00";               # When to update
      keepGenerations = 7;                  # GC after update (0 = skip)
    };
    
    # --- Xen Orchestra Updates ---
    # Update XO upstream source and rebuild
    xoa = {
      enable = false;                       # Enable: true | Disable: false
      schedule = "Tue 04:00";               # When to update
      keepGenerations = 7;                  # GC after update (0 = skip)
    };
  };
  
  # ============================================================================
  # ADVANCED SETTINGS (usually don't change)
  # ============================================================================
  
  # Service account for running XO (non-root, no login)
  xoUser = "xo";
  xoGroup = "xo";
  
  # NixOS state version (matches your NixOS release)
  # DO NOT CHANGE after initial installation
  stateVersion = "25.05";
}