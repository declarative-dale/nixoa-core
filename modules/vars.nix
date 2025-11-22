# vars.nix - Centralized Configuration for XOA Deployment
# ============================================================================
# This file contains all user-configurable settings for your Xen Orchestra
# deployment. Edit this file to customize your installation.
# ============================================================================

{
  # ============================================================================
  # REQUIRED SETTINGS - Must be configured before deployment
  # ============================================================================
  
  # System architecture (usually x86_64-linux)
  system = "x86_64-linux";
  
  # Hostname for this NixOS system
  hostname = "xoa";
  
  # Admin username for SSH access (will have full sudo rights)
  username = "xoa";
  
  # SSH public keys for admin user (REQUIRED - at least one)
  # Generate with: ssh-keygen -t ed25519 -C "your-email@example.com"
  # Then add the contents of ~/.ssh/id_ed25519.pub here
  sshKeys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host"
  ];
  
  # ============================================================================
  # XEN ORCHESTRA CONFIGURATION
  # ============================================================================
  
  # Network binding address
  # - "0.0.0.0" = listen on all interfaces (typical for servers)
  # - "127.0.0.1" = localhost only (for testing)
  # - Specific IP = bind to specific interface
  xoHost = "0.0.0.0";
  
  # Web interface ports
  xoPort = 80;        # HTTP port
  xoHttpsPort = 443;  # HTTPS port
  
  # TLS/SSL configuration
  tls = {
    enable = true;                          # Enable HTTPS with self-signed cert
    dir = "/etc/ssl/xo";                    # Certificate directory
    cert = "/etc/ssl/xo/certificate.pem";   # Certificate file
    key = "/etc/ssl/xo/key.pem";            # Private key file
  };
  
  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================
  
  networking = {
    firewall = {
      # Open ports for XO and various console protocols
      allowedTCPPorts = [ 
        80      # HTTP
        443     # HTTPS
        3389    # RDP console
        5900    # VNC console
        8012    # Additional XO service port
      ];
    };
  };
  
  # ============================================================================
  # STORAGE & BACKUP CONFIGURATION
  # ============================================================================
  
  storage = {
    # Enable support for different storage types
    nfs = {
      enable = true;  # Network File System support
    };
    
    cifs = {
      enable = true;  # Windows/SMB share support
    };
    
    vhd = {
      enable = true;  # VHD/VHDX disk image support (via libvhdi)
    };
    
    # Base directory for remote storage mounts
    mountsDir = "/var/lib/xo/mounts";
  };
  
  # ============================================================================
  # AUTOMATED UPDATES & MAINTENANCE
  # ============================================================================
  
  updates = {
    # Repository location (where this flake is stored)
    # Common locations:
    #   "/etc/nixos/xoa-flake"  - System-wide (recommended for production)
    #   "/opt/xoa-flake"        - Alternative system location
    #   "~/xoa-flake"           - User directory (for testing)
    repoDir = "/etc/nixos/xoa-flake";
    
    # Files to protect from git operations (never overwrite)
    protectPaths = [ 
      "vars.nix"                    # This configuration file
      "hardware-configuration.nix"  # Hardware-specific config
    ];
    
    # --- Update Monitoring & Notifications ---
    monitoring = {
      # Send notifications for successful updates (not just failures)
      notifyOnSuccess = false;
      
      # Email notifications (requires postfix or similar MTA)
      email = {
        enable = false;
        to = "admin@example.com";
        from = "xoa@example.com";  # Optional sender address
      };
      
      # ntfy.sh push notifications (works with mobile apps)
      # Get the app: https://ntfy.sh/
      ntfy = {
        enable = false;
        server = "https://ntfy.sh";         # Or your self-hosted instance
        topic = "xoa-updates-${hostname}";  # Unique topic per server
        priority = "default";                # min, low, default, high, urgent
      };
      
      # Generic webhook (Discord, Slack, Teams, etc.)
      webhook = {
        enable = false;
        url = "";  # Full webhook URL
        method = "POST";  # HTTP method
      };
    };
    
    # --- Garbage Collection ---
    # Clean up old system generations to save disk space
    gc = {
      enable = true;                  # Recommended for production
      schedule = "Sun 03:00";         # When to run (systemd calendar)
      keepGenerations = 10;           # Number of generations to keep
    };
    
    # --- Flake Self-Update ---
    # Pull latest configuration from git repository
    flake = {
      enable = false;                 # Enable when ready for production
      schedule = "Sun 02:00";         # When to check for updates
      remoteUrl = "https://github.com/yourusername/xoa-flake.git";
      branch = "main";                # Branch to track
      autoRebuild = false;            # Auto-rebuild after pull (careful!)
    };
    
    # --- NixOS System Updates ---
    # Update nixpkgs for security patches and package updates
    nixpkgs = {
      enable = false;                 # Enable for automatic security updates
      schedule = "Mon 02:00";         # When to update
      keepGenerations = 10;           # Cleanup after update
    };
    
    # --- Xen Orchestra Updates ---
    # Update XO to latest upstream version
    xoa = {
      enable = false;                 # Enable for automatic XO updates
      schedule = "Tue 02:00";         # When to update
      keepGenerations = 10;           # Cleanup after update
      
      # Optional: Pin to specific branch/tag
      # branch = "master";            # Or specific version tag
    };
  };
  
  # ============================================================================
  # ADVANCED SETTINGS (usually don't need to change)
  # ============================================================================
  
  # Service account for running XO (non-root, system user)
  xoUser = "xo";
  xoGroup = "xo";
  
  # Performance tuning
  performance = {
    # Node.js memory limit for XO build (MB)
    nodeBuildMemory = 4096;
    
    # Redis memory limit
    redisMaxMemory = "256mb";
  };
  
  # Development/debug options
  debug = {
    # Keep build logs
    keepBuildLogs = false;
    
    # Verbose systemd logging
    verboseServices = false;
  };
  
  # ============================================================================
  # STATE VERSION - DO NOT CHANGE AFTER INSTALLATION
  # ============================================================================
  # This should match the NixOS version you initially installed with.
  # Changing this after installation can cause issues with stateful services.
  stateVersion = "25.05";
}
