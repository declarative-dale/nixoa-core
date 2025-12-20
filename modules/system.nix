# SPDX-License-Identifier: Apache-2.0
{ config, pkgs, lib, ... }:

let
  cfg = config.nixoa;
in
{
  # ============================================================================
  # SYSTEM IDENTIFICATION
  # ============================================================================

  networking.hostName = cfg.hostname;

  # ============================================================================
  # LOCALE & INTERNATIONALIZATION
  # ============================================================================

  time.timeZone = lib.mkDefault cfg.timezone;
  
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

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Alternative for VMs using BIOS/legacy boot:
  # boot.loader.grub = {
  #   enable = true;
  #   device = "/dev/sda";  # or /dev/vda, /dev/xvda for Xen
  # };

  # ============================================================================
  # KERNEL & FILESYSTEM SUPPORT
  # ============================================================================

  # Note: Filesystem support (NFS, CIFS) is configured in storage.nix
  # to avoid duplication and ensure consistency

  # Note: All services configuration is consolidated below after the Nix configuration section
  # to avoid conflicts with custom services from nixoa.toml

  # Ensure NFS client utilities and services are available
  boot.initrd.supportedFilesystems = [ "nfs" ];
  boot.initrd.kernelModules = [ "nfs" ];

  # Kernel parameters (optional, useful for VMs)
  # boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

  # ============================================================================
  # XEN GUEST SUPPORT
  # ============================================================================
  
  # Xen guest agent for better VM integration
  systemd.packages = [ pkgs.xen-guest-agent ];
  systemd.services.xen-guest-agent.wantedBy = [ "multi-user.target" ];

  # ============================================================================
  # USER ACCOUNTS
  # ============================================================================
  
  # Primary group for XO service
  users.groups.${cfg.xo.service.group} = {};
  users.groups.fuse = {};

  # XO service account (runs xo-server and related services)
  users.users.${cfg.xo.service.user} = {
    isSystemUser = true;
    description = "Xen Orchestra service account";
    createHome = true;
    group = cfg.xo.service.group;
    home = "/var/lib/xo";
    shell = lib.mkDefault "${pkgs.shadow}/bin/nologin";
    extraGroups = [ "fuse" ];
  };

  # XOA admin account: SSH-key login only, sudo-capable
  users.users.${cfg.admin.username} = {
    isNormalUser = true;
    description = "Xen Orchestra Administrator";
    createHome = true;
    home = "/home/${cfg.admin.username}";
    # shell is already provided by isNormalUser = true (defaults to bash)
    # Home Manager will set shell to zsh if extras.enable = true
    extraGroups = [ "wheel" "systemd-journal" ];

    # Locked password - SSH key authentication only
    hashedPassword = "!";

    openssh.authorizedKeys.keys = cfg.admin.sshKeys;

    # User packages are now managed by Home Manager
    # (removed packages attribute - see user-config/home/home.nix)
  };

  # ============================================================================
  # SECURITY & SUDO
  # ============================================================================
  
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;

    extraRules = [
      # Admin user with full sudo access
      {
        users = [ cfg.admin.username ];
        commands = [
          { command = "ALL"; options = [ "NOPASSWD" ]; }
        ];
      }

      # Note: XO service account sudo rules are configured in storage.nix
      # to avoid duplication and ensure all mount/vhd operations are covered
    ];
  };

  # ============================================================================
  # NETWORKING
  # ============================================================================
  
  # Enable networking
  networking.networkmanager.enable = lib.mkDefault false;
  systemd.network.enable = lib.mkDefault true;
  networking.useNetworkd = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = cfg.networking.firewall.allowedTCPPorts;

    # Optional: Allow ping
    allowPing = true;

    # Log dropped packets (useful for debugging)
    logRefusedConnections = lib.mkDefault false;
  };

  # ============================================================================
  # SSH SERVICE
  # ============================================================================

  # SSH configuration moved to consolidated services block below

  # Note: FUSE support is configured in storage.nix

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================
  
  environment.systemPackages = with pkgs; [
    # Core utilities
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

    # System administration
    git
    rsync
    lsof
    iotop
    sysstat
    dool  # dstat replacement

    # Network tools
    nfs-utils
    cifs-utils
    nettools
    nmap
    tcpdump
    dig
    traceroute

    # XO dependencies
    nodejs_20
    yarn
    python3
    gcc
    gnumake
    pkg-config
    openssl

    # Monitoring
    prometheus-node-exporter
  ] ++ (map (name:
    if pkgs ? ${name}
    then pkgs.${name}
    else throw ''
      Package "${name}" not found in nixpkgs.
      Check spelling or remove from system-settings.toml [packages.system] extra array.
    ''
  ) cfg.packages.system.extra);

  # ============================================================================
  # NIX CONFIGURATION
  # ============================================================================
  
  nix = {
    # Enable flakes and new command interface
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      
      # Build optimization
      auto-optimise-store = true;
      
      # Trusted users (can use binary caches)
      trusted-users = [ "root" cfg.admin.username ];
      
      # Prevent disk space issues
      min-free = lib.mkDefault (1024 * 1024 * 1024); # 1GB
      max-free = lib.mkDefault (5 * 1024 * 1024 * 1024); # 5GB
    };
    
    # Garbage collection
    gc = {
      automatic = false;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    
    # Optimize store on a schedule
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================

  # All services are defined here in one place to avoid conflicts
  # This includes built-in services, SSH, monitoring, logging, and custom services from nixoa.toml
  services = lib.mkMerge [
    # Built-in services for NFS support
    {
      rpcbind.enable = true;  # Required for NFSv3
      nfs.server.enable = false;  # We're a client, not a server

      # SSH configuration
      openssh = {
        enable = true;
        openFirewall = true;

        settings = {
          PermitRootLogin = "no";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PubkeyAuthentication = true;
          AllowUsers = [ cfg.admin.username ];

          # Security hardening
          X11Forwarding = false;
          PermitEmptyPasswords = false;
          Protocol = 2;
          ClientAliveInterval = 300;
          ClientAliveCountMax = 2;
        };

        # Host keys (let sshd generate them on first boot)
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

      # libvhdi support for VHD operations
      libvhdi.enable = true;

      # Prometheus node exporter for monitoring (optional)
      prometheus.exporters.node = {
        enable = lib.mkDefault false;
        port = 9100;
        openFirewall = false;

        enabledCollectors = [
          "conntrack"
          "diskstats"
          "entropy"
          "filefd"
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "netstat"
          "stat"
          "time"
          "uname"
          "vmstat"
        ];
      };

      # Journald logging configuration
      journald.extraConfig = ''
        # Persistent storage
        Storage=persistent

        # Disk usage limits
        SystemMaxUse=1G
        SystemMaxFileSize=100M

        # Retention
        MaxRetentionSec=30d

        # Forward to console for debugging
        ForwardToConsole=no

        # Compression
        Compress=yes
      '';
    }
    # Custom services from user-config [services] section
    # Users can enable services with defaults: services.enable = ["docker", "tailscale"]
    # Or configure with options: [services.docker] enable = true, enableOnBoot = true
    # Note: Service names are validated by NixOS module system at evaluation time
    # Invalid service names will produce clear error messages
    cfg.services.definitions
  ];

  # ============================================================================
  # XEN ORCHESTRA SERVICE CONFIGURATION
  # ============================================================================

  # Main XOA module configuration
  # Bridge config.nixoa.* to config.xoa.* (internal XOA module options)
  xoa = {
    enable = true;

    admin = {
      user = cfg.admin.username;
      sshAuthorizedKeys = cfg.admin.sshKeys;
    };

    xo = {
      user = cfg.xo.service.user;
      group = cfg.xo.service.group;
      host = cfg.xo.host;
      port = cfg.xo.port;
      httpsPort = cfg.xo.httpsPort;

      ssl = {
        enable = cfg.xo.tls.enable;
        redirectToHttps = cfg.xo.tls.redirectToHttps;
        dir = cfg.xo.tls.dir;
        cert = cfg.xo.tls.cert;
        key = cfg.xo.tls.key;
      };

      # Network isolation during build
      buildIsolation = true;
    };

    # Automatic TLS certificate generation
    autocert = {
      enable = cfg.xo.tls.autoGenerate;
    };

    storage = {
      nfs.enable = cfg.storage.nfs.enable;
      cifs.enable = cfg.storage.cifs.enable;
      vhd.enable = cfg.storage.vhd.enable;
      mountsDir = cfg.storage.mountsDir;
    };
  };

  # Enable libvhdi support for VHD operations (moved to consolidated services block)

  # xo-server capabilities - needs to run sudo for mounting operations
  systemd.services.xo-server.serviceConfig = {
    # Capabilities needed for normal operation
    AmbientCapabilities = lib.mkForce [
      "CAP_NET_BIND_SERVICE"  # Bind to ports 80/443
      "CAP_SETUID"            # Required for sudo to switch users
      "CAP_SETGID"            # Required for sudo to switch groups
    ];
    # Don't restrict CapabilityBoundingSet - mount.cifs needs unrestricted caps
    # The service itself only gets the AmbientCapabilities, but child processes
    # (like sudo->mount->mount.cifs) can gain more via setuid
    CapabilityBoundingSet = lib.mkForce [ ];

    # Ensure NoNewPrivileges is disabled so sudo/setuid wrappers work
    NoNewPrivileges = lib.mkForce false;
  };

  # Pass update configuration to updates module
  updates = cfg.updates;

  # Pass extras configuration to extras module
  xoa.extras = cfg.extras;

  # ============================================================================
  # SYSTEM MONITORING (OPTIONAL)
  # ============================================================================

  # Prometheus configuration moved to consolidated services block below

  # ============================================================================
  # LOGGING & JOURNALD
  # ============================================================================

  # Journald configuration moved to consolidated services block below

  # ============================================================================
  # PERFORMANCE TUNING
  # ============================================================================
  
  # Swappiness (lower = less swap usage)
  boot.kernel.sysctl = {
    "vm.swappiness" = lib.mkDefault 10;
    
    # Network tuning for XO
    "net.core.somaxconn" = 1024;
    "net.ipv4.tcp_max_syn_backlog" = 2048;
    
    # File handle limits
    "fs.file-max" = 1000000;
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 524288;
  };

  # System limits
  security.pam.loginLimits = [
    {
      domain = cfg.xo.service.user;
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = cfg.xo.service.user;
      type = "hard";
      item = "nofile";
      value = "1048576";
    }
  ];

  # ============================================================================
  # STATE VERSION
  # ============================================================================

  # DO NOT CHANGE after initial installation
  system.stateVersion = cfg.stateVersion;
}
