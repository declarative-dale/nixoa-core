# vars.nix - User Configuration for XOA Deployment
# ============================================================================
# Edit this file to customize your Xen Orchestra installation
# ============================================================================

{
  # ============================================================================
  # REQUIRED SETTINGS - Must be configured before deployment
  # ============================================================================
  
  # System architecture
  system = "x86_64-linux";
  
  # Hostname for this NixOS system
  hostname = "xoa";
  
  # Admin username for SSH access (will have full sudo rights)
  username = "xoa";
  
  # SSH public keys for admin user (REQUIRED - at least one)
  # Generate with: ssh-keygen -t ed25519 -C "your-email@example.com"
  sshKeys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host"
  ];
  
  # ============================================================================
  # XEN ORCHESTRA CONFIGURATION
  # ============================================================================
  
  # Network binding (0.0.0.0 = all interfaces, 127.0.0.1 = localhost only)
  xoHost = "0.0.0.0";
  
  # Web interface ports
  xoPort = 80;
  xoHttpsPort = 443;
  
  # TLS/SSL configuration
  tls = {
    enable = true;                          # Auto-generate self-signed certificates
    redirectToHttps = true;                 # Redirect HTTP to HTTPS
    dir = "/etc/ssl/xo";                    # Certificate storage directory
    cert = "/etc/ssl/xo/certificate.pem";   # Certificate file path
    key = "/etc/ssl/xo/key.pem";            # Private key file path
  };

  # Enable Xen Orchestra v6 preview (accessible at /v6)
  enableV6Preview = false;
  
  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================
  
  networking = {
    firewall = {
      # Open ports for XO and console access
      allowedTCPPorts = [ 
        80      # HTTP
        443     # HTTPS
        3389    # RDP console
        5900    # VNC console
        8012    # XO service port
      ];
    };
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
  # TERMINAL ENHANCEMENTS (disabled by default)
  # ============================================================================

  extras = {
    enable = false;                         # Enhanced terminal experience (zsh, oh-my-posh, fzf, etc.)
  };
  
  # ============================================================================
  # AUTOMATED UPDATES (all disabled by default)
  # ============================================================================
  
  updates = {
    # Location of this flake repository
    repoDir = "~/nixoa";
    
    # Files to protect from git operations
    protectPaths = [ "vars.nix" "hardware-configuration.nix" ];
    
    # Monitoring & Notifications
    monitoring = {
      notifyOnSuccess = false;              # Notify on success (not just failures)
      
      # Email notifications
      email = {
        enable = false;
        to = "admin@example.com";
      };
      
      # ntfy.sh push notifications
      ntfy = {
        enable = false;
        server = "https://ntfy.sh";
        topic = "xoa-updates";              # Change to unique topic
      };
      
      # Webhook notifications
      webhook = {
        enable = false;
        url = "";                           # Webhook URL
      };
    };
    
    # Garbage Collection
    gc = {
      enable = false;
      schedule = "Sun 04:00";
      keepGenerations = 7;
    };
    
    # Flake Self-Update (pull from git)
    flake = {
      enable = false;
      schedule = "Sun 04:00";
      remoteUrl = "https://codeberg.org/dalemorgan/declarative-xoa-ce.git";
      branch = "main";
      autoRebuild = false;
    };
    
    # NixOS Updates
    nixpkgs = {
      enable = false;
      schedule = "Mon 04:00";
      keepGenerations = 7;
    };
    
    # Xen Orchestra Updates
    xoa = {
      enable = false;
      schedule = "Tue 04:00";
      keepGenerations = 7;
    };
    
    # libvhdi Updates
    libvhdi = {
      enable = false;
      schedule = "Wed 04:00";
      keepGenerations = 7;
    };
  };
  
  # ============================================================================
  # SERVICE ACCOUNT SETTINGS
  # ============================================================================
  
  # XO service account (non-root, system user)
  xoUser = "xo";
  xoGroup = "xo";
  
  # ============================================================================
  # NIXOS STATE VERSION - DO NOT CHANGE
  # ============================================================================
  # This should match the NixOS version you initially installed with.
  stateVersion = "25.05";
}
