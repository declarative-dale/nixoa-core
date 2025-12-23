# SPDX-License-Identifier: Apache-2.0
{ config, pkgs, lib, systemSettings ? {}, userSettings ? {}, ... }:

let
  # Safe attribute access with defaults
  get = path: default:
    let
      getValue = cfg: pathList:
        if pathList == []
        then cfg
        else if builtins.isAttrs cfg && builtins.hasAttr (builtins.head pathList) cfg
        then getValue cfg.${builtins.head pathList} (builtins.tail pathList)
        else null;
      result = getValue systemSettings path;
    in
      if result == null then default else result;

  # Extract commonly used values
  hostname = get ["hostname"] "nixoa";
  username = get ["username"] "xoa";
  stateVersion = get ["stateVersion"] "25.11";
  timezone = get ["timezone"] "UTC";
  sshKeys = get ["sshKeys"] [];
  extrasEnable = userSettings.extras.enable or false;
  systemPackagesExtra = get ["packages" "system" "extra"] [];
  allowedTCPPorts = get ["networking" "firewall" "allowedTCPPorts"] [80 443 3389 5900 8012];
  xoServiceUser = get ["xo" "service" "user"] "xo";
  xoServiceGroup = get ["xo" "service" "group"] "xo";
  xoHost = get ["xo" "host"] "0.0.0.0";
  xoPort = get ["xo" "port"] 80;
  xoHttpsPort = get ["xo" "httpsPort"] 443;
  xoTlsEnable = get ["xo" "tls" "enable"] true;
  xoTlsRedirect = get ["xo" "tls" "redirectToHttps"] true;
  xoTlsAutoGen = get ["xo" "tls" "autoGenerate"] true;
  xoTlsDir = get ["xo" "tls" "dir"] "/etc/ssl/xo";
  xoTlsCert = get ["xo" "tls" "cert"] "/etc/ssl/xo/certificate.pem";
  xoTlsKey = get ["xo" "tls" "key"] "/etc/ssl/xo/key.pem";
  storageNfsEnable = get ["storage" "nfs" "enable"] true;
  storageCifsEnable = get ["storage" "cifs" "enable"] true;
  storageVhdEnable = get ["storage" "vhd" "enable"] true;
  storageMountsDir = get ["storage" "mountsDir"] "/var/lib/xo/mounts";
  servicesDefinitions = get ["services" "definitions"] {};
  updatesConfig = get ["updates"] {};
in
{
  # ============================================================================
  # SYSTEM IDENTIFICATION
  # ============================================================================

  networking.hostName = hostname;

  # ============================================================================
  # LOCALE & INTERNATIONALIZATION
  # ============================================================================

  time.timeZone = lib.mkDefault timezone;
  
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
  # SHELLS
  # ============================================================================

  # Ensure both bash and zsh are valid login shells for the system
  # Shell selection per-user is configured in users.users.<name>.shell
  environment.shells = [ pkgs.bashInteractive pkgs.zsh ];

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
  users.groups.${xoServiceGroup} = {};
  users.groups.fuse = {};

  # XO service account (runs xo-server and related services)
  users.users.${xoServiceUser} = {
    isSystemUser = true;
    description = "Xen Orchestra service account";
    createHome = true;
    group = xoServiceGroup;
    home = "/var/lib/xo";
    shell = lib.mkDefault "${pkgs.shadow}/bin/nologin";
    extraGroups = [ "fuse" ];
  };

  # XOA admin account: SSH-key login only, sudo-capable
  users.users.${username} = {
    isNormalUser = true;
    description = "Xen Orchestra Administrator";
    createHome = true;
    home = "/home/${username}";
    # Shell selection based on extras.enable in configuration.nix
    # extras.enable=false → bash (default), extras.enable=true → zsh
    shell = if extrasEnable then pkgs.zsh else pkgs.bashInteractive;
    extraGroups = [ "wheel" "systemd-journal" ];

    # Locked password - SSH key authentication only
    hashedPassword = "!";

    openssh.authorizedKeys.keys = sshKeys;

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
        users = [ username ];
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
    allowedTCPPorts = allowedTCPPorts;

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
      Check spelling or remove from configuration.nix systemSettings.packages.system.extra.
    ''
  ) systemPackagesExtra);

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
      trusted-users = [ "root" username ];
      
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
          AllowUsers = [ username ];

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
    # Custom services from user-config services.definitions
    # Users can define services with custom configurations
    # Note: Service names are validated by NixOS module system at evaluation time
    # Invalid service names will produce clear error messages
    servicesDefinitions
  ];

  # ============================================================================
  # XEN ORCHESTRA SERVICE CONFIGURATION
  # ============================================================================

  # Main XOA module configuration
  # Configure XO service based on systemSettings
  xoa = {
    enable = true;

    admin = {
      user = username;
      sshAuthorizedKeys = sshKeys;
    };

    xo = {
      user = xoServiceUser;
      group = xoServiceGroup;
      host = xoHost;
      port = xoPort;
      httpsPort = xoHttpsPort;

      ssl = {
        enable = xoTlsEnable;
        redirectToHttps = xoTlsRedirect;
        dir = xoTlsDir;
        cert = xoTlsCert;
        key = xoTlsKey;
      };

      # Network isolation during build
      buildIsolation = true;
    };

    # Automatic TLS certificate generation
    autocert = {
      enable = xoTlsAutoGen;
    };

    storage = {
      nfs.enable = storageNfsEnable;
      cifs.enable = storageCifsEnable;
      vhd.enable = storageVhdEnable;
      mountsDir = storageMountsDir;
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
  updates = updatesConfig;

  # Pass extras configuration to extras module
  xoa.extras = userSettings.extras or {};

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
      domain = xoServiceUser;
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = xoServiceUser;
      type = "hard";
      item = "nofile";
      value = "1048576";
    }
  ];

  # ============================================================================
  # STATE VERSION
  # ============================================================================

  # DO NOT CHANGE after initial installation
  system.stateVersion = stateVersion;
}
